import UIKit

struct AnalysisDependencies {
    var loadPhoto: (String) -> UIImage?
    var loadAnalyses: () -> [ScanAnalysis]
    var saveAnalysis: (ScanAnalysis) -> Void
    var insightProvider: any InsightRequesting
    var clock: () -> Date
    var thresholds: AnalysisThresholdSet

    static let live = AnalysisDependencies(
        loadPhoto: { PhotoStore.loadImage(named: $0) },
        loadAnalyses: { AnalysisStore.loadAll() },
        saveAnalysis: { AnalysisStore.save($0) },
        insightProvider: NetworkProxy.shared,
        clock: Date.init,
        thresholds: .engineeringV1
    )
}

/// Orchestrates on-device visual analysis. Missing evidence remains unavailable;
/// no stage is permitted to fabricate a landmark, a passing result, or a zero.
@MainActor
final class AnalysisPipeline {
    static let shared = AnalysisPipeline()

    private let dependencies: AnalysisDependencies

    init(dependencies: AnalysisDependencies = .live) {
        self.dependencies = dependencies
    }

    func analyzeNewScan(
        scan: Scan,
        allScans: [Scan],
        measurements: [Measurement],
        profile: UserProfile
    ) async -> ScanAnalysis {
        let startedAt = dependencies.clock()
        let scanId = scan.id
        let eligibleDates = Dictionary(uniqueKeysWithValues: allScans
            .filter(\.isCanonicalProgressScan)
            .map { ($0.id, $0.date) })
        let priorAnalyses = dependencies.loadAnalyses()
            .filter { $0.analysisVersion == AnalysisStore.currentAnalysisVersion }
            .filter { prior in
                guard prior.id != scanId, let priorDate = eligibleDates[prior.id] else { return false }
                return priorDate < scan.date
            }
            .sorted { (eligibleDates[$0.id] ?? .distantPast) < (eligibleDates[$1.id] ?? .distantPast) }
        let baseline = priorAnalyses.first

        var assessments: [Pose: CaptureAssessment] = [:]
        var preparedImages: [Pose: UIImage] = [:]
        var failures: [String: String] = [:]

        for capture in scan.standardCaptures {
            guard let loaded = dependencies.loadPhoto(capture.imageFilename) else {
                assessments[capture.pose] = .legacyUnverified()
                failures[capture.pose.rawValue] = "photo_load_failed"
                continue
            }
            let prepared = PhotoStore.prepare(loaded)
            preparedImages[capture.pose] = prepared.image
            if let storedAssessment = capture.assessment {
                assessments[capture.pose] = storedAssessment
            } else {
                assessments[capture.pose] = await QualityGateEngine.assessWithTimeout(
                    image: prepared.image,
                    expectedPose: capture.pose,
                    seconds: 5
                )
            }
        }

        let qualityResult = aggregateQuality(assessments)
        let cameraMetadata = Dictionary(uniqueKeysWithValues: scan.standardCaptures.compactMap { capture in
            capture.cameraMetadata.map { (capture.pose, $0) }
        })
        var extractedPoses: [ExtractedPose] = []
        var silhouetteProfiles: [SilhouetteProfile] = []

        for capture in scan.standardCaptures {
            guard let image = preparedImages[capture.pose] else { continue }
            do {
                var extracted = try await BodyPoseExtractor.extract(
                    from: image,
                    pose: capture.pose,
                    scanId: scanId
                )
                if let baselinePose = baseline?.extractedPoses.first(where: { $0.pose == capture.pose }) {
                    extracted.poseMatchScore = NormalizationEngine.computePoseMatchScore(
                        a: extracted,
                        b: baselinePose
                    )
                }
                // Persist raw image-space landmarks. Normalized landmarks are used
                // only inside pose matching; mask sampling requires image space.
                extractedPoses.append(extracted)

                do {
                    let silhouette = try await SilhouetteAnalyzer.analyze(
                        image: image,
                        extractedPose: extracted
                    )
                    if silhouette.supportedRegions?.isEmpty == false {
                        silhouetteProfiles.append(silhouette)
                    } else {
                        failures["\(capture.pose.rawValue)_silhouette"] = "no_supported_regions"
                    }
                } catch {
                    failures["\(capture.pose.rawValue)_silhouette"] = String(describing: error)
                }
            } catch {
                failures[capture.pose.rawValue] = String(describing: error)
            }
        }

        let visualSignals = VisualSignalEngine.compute(
            currentProfiles: silhouetteProfiles,
            allScanAnalyses: priorAnalyses,
            currentCameraMetadata: cameraMetadata,
            thresholds: dependencies.thresholds
        )
        let availability = determineAvailability(
            isFirstScan: priorAnalyses.isEmpty,
            profiles: silhouetteProfiles,
            visualSignals: visualSignals
        )
        let smoothedSignals = TrendSmoothingEngine.smooth(
            allAnalyses: priorAnalyses,
            currentVisualSignals: visualSignals
        )
        let patterns = RecompositionDetector.detect(
            smoothed: smoothedSignals,
            measurements: measurements,
            goal: profile.goal
        )
        let analyzedAt = dependencies.clock()
        let interpreted = SignalInterpreter.interpret(
            smoothed: smoothedSignals,
            visualSignals: visualSignals,
            measurements: measurements,
            profile: profile,
            recompositionPatterns: patterns,
            qualityResult: qualityResult,
            assessments: assessments,
            analysisAvailability: availability,
            allAnalyses: priorAnalyses,
            scanContext: scan.context,
            thresholds: dependencies.thresholds,
            now: analyzedAt
        )

        let measurementAlignmentScore = ConfidenceEngine.measurementAgreementScore(
            from: interpreted.measurementAlignment
        )
        let poseScores = extractedPoses.compactMap(\.poseMatchScore)
        let averagePoseMatch = poseScores.isEmpty ? nil : poseScores.reduce(0, +) / Float(poseScores.count)
        let confidence = ConfidenceEngine.compute(
            scanCount: priorAnalyses.count + 1,
            qualityResult: qualityResult,
            assessments: assessments,
            analysisAvailability: availability,
            poseMatchScore: averagePoseMatch,
            measurementAgreementScore: measurementAlignmentScore,
            allAnalyses: priorAnalyses,
            goal: profile.goal,
            recompositionPatterns: patterns,
            regionalComparisons: visualSignals.regionalComparisons,
            thresholdsValidated: dependencies.thresholds.isValidated,
            now: analyzedAt
        )

        let encodedAssessments = Dictionary(uniqueKeysWithValues: assessments.map {
            ($0.key.rawValue, $0.value)
        })
        let metadata = AnalysisAlgorithmMetadata(
            analysisVersion: AnalysisStore.currentAnalysisVersion,
            bodyPoseRevision: BodyPoseExtractor.bodyPoseRevision,
            personSegmentationRevision: SilhouetteAnalyzer.personSegmentationRevision,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            thresholdSetIdentifier: dependencies.thresholds.identifier
        )
        let intermediate = ScanAnalysis(
            id: scanId,
            analysisVersion: AnalysisStore.currentAnalysisVersion,
            analyzedAt: analyzedAt,
            qualityResult: qualityResult,
            extractedPoses: extractedPoses,
            silhouetteProfiles: silhouetteProfiles,
            visualSignals: visualSignals,
            smoothedSignals: smoothedSignals,
            confidence: confidence,
            interpretedSignals: interpreted,
            generatedInsight: nil,
            captureAssessments: encodedAssessments,
            analysisAvailability: availability,
            poseFailures: failures.isEmpty ? nil : failures,
            algorithmMetadata: metadata,
            captureCameraMetadata: Dictionary(uniqueKeysWithValues: cameraMetadata.map {
                ($0.key.rawValue, $0.value)
            })
        )
        dependencies.saveAnalysis(intermediate)

        let insight = await InsightEngine.generateInsight(
            signals: interpreted,
            networkProxy: dependencies.insightProvider,
            allowCloud: profile.usesCloudInsights,
            now: analyzedAt
        )
        var final = intermediate
        final.generatedInsight = insight
        dependencies.saveAnalysis(final)

        _ = analyzedAt.timeIntervalSince(startedAt) // retained for fixture report clocks
        return final
    }

    private func determineAvailability(
        isFirstScan: Bool,
        profiles: [SilhouetteProfile],
        visualSignals: VisualSignalSet
    ) -> AnalysisAvailability {
        if isFirstScan { return .baselineOnly }
        guard !profiles.isEmpty else { return .processingFailed }
        let supported = visualSignals.regionalComparisons?.contains { $0.status != .unavailable } == true
        return supported ? .comparable : .partialEvidence
    }

    private func aggregateQuality(_ assessments: [Pose: CaptureAssessment]) -> QualityGateResult {
        let values = Pose.required.compactMap { assessments[$0] }
        guard !values.isEmpty else {
            return QualityGateEngine.qualityResult(
                from: QualityGateEngine.unavailableAssessment(reason: "no_capture_assessments")
            )
        }
        let issues = Array(Set(values.flatMap(\.confirmedIssues)))
        let brightness = values.map(\.brightnessScore).reduce(0, +) / Float(values.count)
        let coverage = values.map(\.coverageScore).reduce(0, +) / Float(values.count)
        let verdict: QualityVerdict = issues.isEmpty ? .pass : .warning(issues)
        return QualityGateResult(
            verdict: verdict,
            issues: issues,
            blurScore: 0,
            brightnessScore: brightness,
            coverageScore: coverage,
            regionalCoverage: [
                "shoulders": minimumEvidence(.shoulders, values),
                "torso": min(minimumEvidence(.chest, values), minimumEvidence(.waist, values)),
                "arms": minimumEvidence(.arms, values),
                "sideTorso": assessments[.side]?.regionEvidence[.sideTorso]?.state == .supported ? 1 : 0
            ]
        )
    }

    private func minimumEvidence(_ region: CaptureRegion, _ assessments: [CaptureAssessment]) -> Float {
        assessments.allSatisfy { $0.regionEvidence[region]?.state == .supported } ? 1 : 0
    }
}
