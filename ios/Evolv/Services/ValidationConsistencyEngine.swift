import Foundation
import UIKit

struct ValidationEvaluationResult {
    var status: ValidationConsistencyStatus
    var comparisonsBySet: [Int: ValidationSetComparison]
    var metadata: AnalysisAlgorithmMetadata
}

/// Runs deterministic, local anchor-to-repeat comparisons. It intentionally
/// has no networking or insight-provider dependency and never smooths across
/// longitudinal progress scans.
enum ValidationConsistencyEngine {
    private struct ProcessedScan {
        var extractedPoses: [ExtractedPose]
        var profiles: [SilhouetteProfile]
        var cameraMetadata: [Pose: CaptureCameraMetadata]
        var pixelSizes: [Pose: NormalizedPixelSize]
        var diagnostics: [ValidationPoseDiagnostic]
    }

    /// Runs the exact pose extractor, person segmentation, silhouette sampler,
    /// and region-feature contract used by the real comparison engine. This is
    /// deliberately not a capture-quality approximation.
    static func preflightBaseline(
        captures: [PoseCapture],
        scanID: UUID = UUID(),
        loadPhoto: @escaping (String) -> UIImage? = { PhotoStore.loadImage(named: $0) },
        now: Date = Date()
    ) async -> ValidationBaselinePreflight {
        var processed = await process(
            captures: captures,
            scanID: scanID,
            setNumber: 1,
            baseline: nil,
            loadPhoto: loadPhoto
        )
        appendRequiredFeatureDiagnostics(to: &processed, setNumber: 1)
        return ValidationBaselinePreflight(
            checkedAt: now,
            captureIDs: Pose.required.compactMap { pose in captures.first { $0.pose == pose }?.id },
            poseEvidence: Pose.required.map { pose in
                let profile = processed.profiles.first { $0.pose == pose }
                return ValidationPoseEvidence(
                    pose: pose,
                    poseExtracted: processed.extractedPoses.contains { $0.pose == pose },
                    silhouetteGenerated: profile != nil,
                    supportedRegions: profile?.regionFeatures?
                        .filter { $0.evidenceReason == nil }
                        .map(\.region) ?? []
                )
            },
            diagnostics: processed.diagnostics.sorted(by: diagnosticSort),
            repeatabilityMetrics: repeatabilityMetrics(from: processed)
        )
    }

    static func evaluate(
        session: ValidationStudySession,
        scans: [Scan],
        loadPhoto: @escaping (String) -> UIImage? = { PhotoStore.loadImage(named: $0) },
        thresholds: AnalysisThresholdSet = .engineeringV1,
        now: Date = Date()
    ) async -> ValidationEvaluationResult {
        let metadata = AnalysisAlgorithmMetadata(
            analysisVersion: AnalysisStore.currentAnalysisVersion,
            bodyPoseRevision: BodyPoseExtractor.bodyPoseRevision,
            personSegmentationRevision: SilhouetteAnalyzer.personSegmentationRevision,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            thresholdSetIdentifier: thresholds.identifier
        )
        let scansByID = Dictionary(uniqueKeysWithValues: scans.map { ($0.id, $0) })
        guard let anchorID = session.anchorScanID,
              let anchor = scansByID[anchorID] else {
            return ValidationEvaluationResult(
                status: .needsReview,
                comparisonsBySet: [:],
                metadata: metadata
            )
        }

        var baseline = await process(
            scan: anchor,
            setNumber: 1,
            baseline: nil,
            loadPhoto: loadPhoto
        )
        appendRequiredFeatureDiagnostics(to: &baseline, setNumber: 1)
        var results: [Int: ValidationSetComparison] = [:]

        for record in session.sets.sorted(by: { $0.setNumber < $1.setNumber }) where record.setNumber > 1 {
            let comparisonStartedAt = Date()
            guard let scan = scansByID[record.scanID] else {
                results[record.setNumber] = ValidationSetComparison(
                    setNumber: record.setNumber,
                    regionalComparisons: [],
                    failures: ["set_\(record.setNumber).scan": "scan_missing"],
                    hasSufficientCoreEvidence: false,
                    processingDurationMilliseconds: Int(Date().timeIntervalSince(comparisonStartedAt) * 1_000),
                    diagnostics: []
                )
                continue
            }
            var current = await process(
                scan: scan,
                setNumber: record.setNumber,
                baseline: baseline,
                loadPhoto: loadPhoto
            )
            appendRequiredFeatureDiagnostics(to: &current, setNumber: record.setNumber)
            results[record.setNumber] = comparison(
                baseline: baseline,
                current: current,
                setNumber: record.setNumber,
                thresholds: thresholds,
                processingDurationMilliseconds: Int(Date().timeIntervalSince(comparisonStartedAt) * 1_000)
            )
        }

        let status = classify(session: session, comparisonsBySet: results)

        _ = now // retained as an injectable seam for deterministic callers
        return ValidationEvaluationResult(
            status: status,
            comparisonsBySet: results,
            metadata: metadata
        )
    }

    /// Runs the exact downstream anchor-to-repeat path before a repeat set can
    /// be committed. Capture IDs are part of the returned contract so any
    /// replacement invalidates this result.
    static func preflightRepeat(
        baselineCaptures: [PoseCapture],
        currentCaptures: [PoseCapture],
        setNumber: Int,
        scanID: UUID = UUID(),
        loadPhoto: @escaping (String) -> UIImage? = { PhotoStore.loadImage(named: $0) },
        thresholds: AnalysisThresholdSet = .engineeringV1,
        now: Date = Date()
    ) async -> ValidationSetPreflight {
        let startedAt = Date()
        var baseline = await process(
            captures: baselineCaptures,
            scanID: scanID,
            setNumber: 1,
            baseline: nil,
            loadPhoto: loadPhoto
        )
        appendRequiredFeatureDiagnostics(to: &baseline, setNumber: 1)
        var current = await process(
            captures: currentCaptures,
            scanID: scanID,
            setNumber: setNumber,
            baseline: baseline,
            loadPhoto: loadPhoto
        )
        appendRequiredFeatureDiagnostics(to: &current, setNumber: setNumber)
        return ValidationSetPreflight(
            checkedAt: now,
            setNumber: setNumber,
            captureIDs: Pose.required.compactMap { pose in
                currentCaptures.first { $0.pose == pose }?.id
            },
            comparison: comparison(
                baseline: baseline,
                current: current,
                setNumber: setNumber,
                thresholds: thresholds,
                processingDurationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
            )
        )
    }

    /// Kept separate from Vision so the safety semantics can be exhaustively
    /// unit-tested. Detector abstention is limited evidence; only a genuine
    /// system error, condition change, comparability change, or unexpected
    /// supported signal requires review.
    static func classify(
        session: ValidationStudySession,
        comparisonsBySet results: [Int: ValidationSetComparison]
    ) -> ValidationConsistencyStatus {
        let hasDeviation = session.statusReasons.isEmpty == false
            || session.sets.contains { record in
                guard let conditions = record.conditions else { return true }
                return !conditions.stayedTheSame || !conditions.deviations.isEmpty
            }
        let hasSystemFailure = results.values.contains { result in
            if let diagnostics = result.diagnostics, !diagnostics.isEmpty {
                return diagnostics.contains { $0.kind == .systemError }
            }
            // Older records and non-pose failures have no typed diagnostics;
            // retaining review semantics is the safest backward-compatible path.
            return !result.failures.isEmpty
        }
        let hasComparabilityChange = results.values.contains { result in
            result.diagnostics?.contains { $0.kind == .comparabilityChange } == true
                || result.regionalComparisons.flatMap(\.contributions).contains { contribution in
                    contribution.reason == "pose_not_comparable"
                        || contribution.reason == "camera_configuration_changed"
                        || contribution.reason == "cross_pose_conflict"
                }
        }
        let hasUnexpectedSignal = results.values.contains { result in
            result.regionalComparisons.contains {
                $0.status == .increase
                    || $0.status == .decrease
                    || $0.reason == "cross_pose_conflict"
            }
        }
        let hasAllFourComparisons = Set(results.keys) == Set(2...5)
        let sufficientCoreEveryTime = hasAllFourComparisons
            && results.values.allSatisfy(\.hasSufficientCoreEvidence)

        if hasDeviation || hasSystemFailure || hasComparabilityChange || hasUnexpectedSignal {
            return .needsReview
        }
        return sufficientCoreEveryTime ? .consistent : .limitedEvidence
    }

    private static func process(
        scan: Scan,
        setNumber: Int,
        baseline: ProcessedScan?,
        loadPhoto: @escaping (String) -> UIImage?
    ) async -> ProcessedScan {
        await process(
            captures: scan.captures,
            scanID: scan.id,
            setNumber: setNumber,
            baseline: baseline,
            loadPhoto: loadPhoto
        )
    }

    private static func process(
        captures: [PoseCapture],
        scanID: UUID,
        setNumber: Int,
        baseline: ProcessedScan?,
        loadPhoto: @escaping (String) -> UIImage?
    ) async -> ProcessedScan {
        var extracted: [ExtractedPose] = []
        var profiles: [SilhouetteProfile] = []
        var diagnostics: [ValidationPoseDiagnostic] = []
        let metadataPairs: [(Pose, CaptureCameraMetadata)] = captures.compactMap { capture in
            guard Pose.required.contains(capture.pose), let metadata = capture.cameraMetadata else { return nil }
            return (capture.pose, metadata)
        }
        let cameraMetadata = Dictionary(uniqueKeysWithValues: metadataPairs)
        var pixelSizes: [Pose: NormalizedPixelSize] = [:]

        for pose in Pose.required {
            guard let capture = captures.first(where: { $0.pose == pose }) else {
                diagnostics.append(diagnostic(
                    setNumber: setNumber,
                    pose: pose,
                    stage: .photoLoading,
                    kind: .systemError,
                    code: "photo_load_failed"
                ))
                continue
            }
            guard let image = loadPhoto(capture.imageFilename) else {
                diagnostics.append(diagnostic(
                    setNumber: setNumber,
                    pose: pose,
                    stage: .photoLoading,
                    kind: .systemError,
                    code: "photo_load_failed"
                ))
                continue
            }
            let prepared = PhotoStore.prepare(image).image
            pixelSizes[pose] = capture.normalizedPixelSize ?? prepared.cgImage.map {
                NormalizedPixelSize(width: $0.width, height: $0.height)
            }
            do {
                var bodyPose = try await BodyPoseExtractor.extract(
                    from: prepared,
                    pose: pose,
                    scanId: scanID
                )
                if let baselinePose = baseline?.extractedPoses.first(where: { $0.pose == pose }) {
                    bodyPose.poseMatchScore = NormalizationEngine.computePoseMatchScore(
                        a: bodyPose,
                        b: baselinePose
                    )
                }
                extracted.append(bodyPose)
                do {
                    let profile = try await SilhouetteAnalyzer.analyze(
                        image: prepared,
                        extractedPose: bodyPose
                    )
                    profiles.append(profile)
                } catch {
                    diagnostics.append(silhouetteDiagnostic(
                        error: error,
                        setNumber: setNumber,
                        pose: pose
                    ))
                }
            } catch {
                diagnostics.append(poseDiagnostic(
                    error: error,
                    setNumber: setNumber,
                    pose: pose
                ))
            }
        }

        return ProcessedScan(
            extractedPoses: extracted,
            profiles: profiles,
            cameraMetadata: cameraMetadata,
            pixelSizes: pixelSizes,
            diagnostics: diagnostics
        )
    }

    private static func comparison(
        baseline: ProcessedScan,
        current: ProcessedScan,
        setNumber: Int,
        thresholds: AnalysisThresholdSet,
        processingDurationMilliseconds: Int
    ) -> ValidationSetComparison {
        let comparisons = VisualSignalEngine.comparePair(
            baselineProfiles: baseline.profiles,
            currentProfiles: current.profiles,
            baselineCameraMetadata: baseline.cameraMetadata,
            currentCameraMetadata: current.cameraMetadata,
            thresholds: thresholds
        )
        let coreRegions: Set<BodyRegion> = [.shoulders, .chest, .waist]
        let supportedCore = Set(comparisons
            .filter { $0.status != .unavailable }
            .map(\.region))
        let comparisonDiagnostics = comparabilityDiagnostics(
            comparisons: comparisons,
            setNumber: setNumber
        )
        let diagnostics = deduplicatedDiagnostics(
            baseline.diagnostics + current.diagnostics + comparisonDiagnostics
        ).sorted(by: diagnosticSort)
        return ValidationSetComparison(
            setNumber: setNumber,
            regionalComparisons: comparisons,
            failures: failureMap(for: diagnostics),
            hasSufficientCoreEvidence: coreRegions.isSubset(of: supportedCore),
            processingDurationMilliseconds: processingDurationMilliseconds,
            diagnostics: diagnostics,
            repeatabilityMetrics: repeatabilityMetrics(from: current)
        )
    }

    private static func comparabilityDiagnostics(
        comparisons: [RegionalComparison],
        setNumber: Int
    ) -> [ValidationPoseDiagnostic] {
        let coreRegions: Set<BodyRegion> = [.shoulders, .chest, .waist]
        var diagnostics: [ValidationPoseDiagnostic] = []
        for comparison in comparisons where coreRegions.contains(comparison.region) {
            for contribution in comparison.contributions where contribution.status == .unavailable {
                guard let reason = contribution.reason else { continue }
                let code: String
                switch reason {
                case "pose_not_comparable":
                    code = contribution.pose == .side
                        ? "side_angle_differs_from_baseline"
                        : "pose_alignment_differs_from_baseline"
                case "camera_configuration_changed", "camera_configuration_unknown":
                    code = "camera_configuration_changed"
                case "pose_match_unavailable":
                    code = "pose_alignment_unavailable"
                default:
                    continue
                }
                diagnostics.append(diagnostic(
                    setNumber: setNumber,
                    pose: contribution.pose,
                    stage: .comparability,
                    kind: .comparabilityChange,
                    code: code,
                    affectedRegions: [comparison.region]
                ))
            }
            if comparison.reason == "cross_pose_conflict" {
                for contribution in comparison.contributions where contribution.status == .supported {
                    diagnostics.append(diagnostic(
                        setNumber: setNumber,
                        pose: contribution.pose,
                        stage: .comparability,
                        kind: .comparabilityChange,
                        code: "cross_pose_evidence_conflict",
                        affectedRegions: [comparison.region]
                    ))
                }
            }
        }
        return diagnostics
    }

    private static func deduplicatedDiagnostics(
        _ diagnostics: [ValidationPoseDiagnostic]
    ) -> [ValidationPoseDiagnostic] {
        var seen = Set<String>()
        return diagnostics.filter { seen.insert($0.id).inserted }
    }

    private static func repeatabilityMetrics(
        from processed: ProcessedScan
    ) -> [ValidationRepeatabilityMetrics] {
        Pose.required.compactMap { pose -> ValidationRepeatabilityMetrics? in
            guard let extracted = processed.extractedPoses.first(where: { $0.pose == pose }) else { return nil }
            let profile = processed.profiles.first(where: { $0.pose == pose })
            let validLandmarks = extracted.landmarks.filter {
                $0.confidence >= (pose == .side ? 0.20 : 0.30)
            }
            let centerX = validLandmarks.isEmpty
                ? nil
                : validLandmarks.map(\.x).reduce(0, +) / Float(validLandmarks.count) - 0.5
            let centerY = validLandmarks.isEmpty
                ? nil
                : validLandmarks.map(\.y).reduce(0, +) / Float(validLandmarks.count) - 0.5
            let margin = validLandmarks.flatMap { [$0.x, $0.y, 1 - $0.x, 1 - $0.y] }.min()
            let size = processed.pixelSizes[pose]
            let scale: Float?
            if let reference = profile?.torsoReferencePixels, let size {
                scale = reference / Float(max(size.width, size.height))
            } else {
                scale = nil
            }
            return ValidationRepeatabilityMetrics(
                pose: pose,
                normalizedFeatureValues: Dictionary(uniqueKeysWithValues:
                    (profile?.regionFeatures ?? []).compactMap { feature in
                        guard feature.evidenceReason == nil else { return nil }
                        return (feature.region, feature.normalizedValue)
                    }
                ),
                normalizedTorsoScale: scale,
                subjectCenterOffsetX: centerX,
                subjectCenterOffsetY: centerY,
                minimumObservedMargin: margin,
                torsoRotationDegrees: torsoRotationDegrees(extracted),
                poseMatchScore: extracted.poseMatchScore
            )
        }
    }

    private static func torsoRotationDegrees(_ pose: ExtractedPose) -> Float? {
        let shoulder: (Float, Float)?
        let hip: (Float, Float)?
        if pose.pose == .side {
            let candidates = ["left", "right"].compactMap { side -> (Float, Float, Float, Float, Float)? in
                guard let shoulder = pose.landmark("\(side)Shoulder"),
                      let hip = pose.landmark("\(side)Hip"),
                      shoulder.confidence >= 0.20, hip.confidence >= 0.20 else { return nil }
                return (shoulder.x, shoulder.y, hip.x, hip.y, min(shoulder.confidence, hip.confidence))
            }
            guard let best = candidates.max(by: { $0.4 < $1.4 }) else { return nil }
            shoulder = (best.0, best.1)
            hip = (best.2, best.3)
        } else {
            guard let ls = pose.landmark("leftShoulder"), let rs = pose.landmark("rightShoulder"),
                  let lh = pose.landmark("leftHip"), let rh = pose.landmark("rightHip") else { return nil }
            shoulder = ((ls.x + rs.x) / 2, (ls.y + rs.y) / 2)
            hip = ((lh.x + rh.x) / 2, (lh.y + rh.y) / 2)
        }
        guard let shoulder, let hip else { return nil }
        let dx = hip.0 - shoulder.0
        let dy = hip.1 - shoulder.1
        guard abs(dx) + abs(dy) > 0.001 else { return nil }
        return atan2(dx, dy) * 180 / .pi
    }

    private static func appendRequiredFeatureDiagnostics(
        to processed: inout ProcessedScan,
        setNumber: Int
    ) {
        let deficits = VisualSignalEngine.baselineEvidenceDeficits(profiles: processed.profiles)
        for pose in Pose.required {
            guard let regions = deficits[pose], !regions.isEmpty else { continue }
            processed.diagnostics.append(diagnostic(
                setNumber: setNumber,
                pose: pose,
                stage: .regionFeatures,
                kind: .evidenceUnavailable,
                code: "required_region_feature_unavailable",
                affectedRegions: regions.sorted { $0.rawValue < $1.rawValue }
            ))
        }
    }

    private static func poseDiagnostic(
        error: Error,
        setNumber: Int,
        pose: Pose
    ) -> ValidationPoseDiagnostic {
        guard let extraction = error as? BodyPoseExtractor.ExtractionError else {
            return diagnostic(
                setNumber: setNumber,
                pose: pose,
                stage: .poseExtraction,
                kind: .systemError,
                code: "unexpected_pose_processing_error"
            )
        }
        switch extraction {
        case .noImage:
            return diagnostic(setNumber: setNumber, pose: pose, stage: .photoLoading, kind: .systemError, code: "image_decode_failed")
        case .hipsUnavailable:
            return diagnostic(setNumber: setNumber, pose: pose, stage: .hipLandmarks, kind: .evidenceUnavailable, code: "hip_landmarks_unavailable")
        case .shouldersUnavailable:
            return diagnostic(setNumber: setNumber, pose: pose, stage: .poseExtraction, kind: .evidenceUnavailable, code: "shoulder_landmarks_unavailable")
        case .noObservation, .insufficientLandmarks:
            return diagnostic(setNumber: setNumber, pose: pose, stage: .poseExtraction, kind: .evidenceUnavailable, code: "body_pose_unavailable")
        }
    }

    private static func silhouetteDiagnostic(
        error: Error,
        setNumber: Int,
        pose: Pose
    ) -> ValidationPoseDiagnostic {
        guard let silhouette = error as? SilhouetteAnalyzer.AnalysisError else {
            return diagnostic(
                setNumber: setNumber,
                pose: pose,
                stage: .silhouette,
                kind: .systemError,
                code: "unexpected_silhouette_processing_error"
            )
        }
        switch silhouette {
        case .noImage:
            return diagnostic(setNumber: setNumber, pose: pose, stage: .photoLoading, kind: .systemError, code: "image_decode_failed")
        case .noSegmentation:
            return diagnostic(setNumber: setNumber, pose: pose, stage: .segmentation, kind: .evidenceUnavailable, code: "person_segmentation_unavailable")
        case .insufficientLandmarks:
            return diagnostic(setNumber: setNumber, pose: pose, stage: .hipLandmarks, kind: .evidenceUnavailable, code: "hip_landmarks_unavailable")
        case .invalidReferenceScale:
            return diagnostic(setNumber: setNumber, pose: pose, stage: .silhouette, kind: .evidenceUnavailable, code: "torso_scale_unavailable")
        case .insufficientEvidence:
            return diagnostic(setNumber: setNumber, pose: pose, stage: .regionFeatures, kind: .evidenceUnavailable, code: "silhouette_evidence_unavailable")
        }
    }

    private static func diagnostic(
        setNumber: Int,
        pose: Pose,
        stage: ValidationEvidenceStage,
        kind: ValidationDiagnosticKind,
        code: String,
        affectedRegions: [BodyRegion] = []
    ) -> ValidationPoseDiagnostic {
        ValidationPoseDiagnostic(
            setNumber: setNumber,
            pose: pose,
            stage: stage,
            kind: kind,
            code: code,
            affectedRegions: affectedRegions
        )
    }

    private static func failureMap(
        for diagnostics: [ValidationPoseDiagnostic]
    ) -> [String: String] {
        diagnostics.reduce(into: [:]) { result, item in
            let key = "set_\(item.setNumber).\(item.pose.rawValue).\(item.stage.rawValue)"
            result[key] = item.code
        }
    }

    private static func diagnosticSort(
        _ lhs: ValidationPoseDiagnostic,
        _ rhs: ValidationPoseDiagnostic
    ) -> Bool {
        if lhs.setNumber != rhs.setNumber { return lhs.setNumber < rhs.setNumber }
        let leftPose = Pose.required.firstIndex(of: lhs.pose) ?? Int.max
        let rightPose = Pose.required.firstIndex(of: rhs.pose) ?? Int.max
        if leftPose != rightPose { return leftPose < rightPose }
        return lhs.stage.rawValue < rhs.stage.rawValue
    }
}
