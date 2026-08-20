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
            diagnostics: processed.diagnostics.sorted(by: diagnosticSort)
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
            let diagnostics = (baseline.diagnostics + current.diagnostics)
                .sorted(by: diagnosticSort)
            results[record.setNumber] = ValidationSetComparison(
                setNumber: record.setNumber,
                regionalComparisons: comparisons,
                failures: failureMap(for: diagnostics),
                hasSufficientCoreEvidence: coreRegions.isSubset(of: supportedCore),
                processingDurationMilliseconds: Int(Date().timeIntervalSince(comparisonStartedAt) * 1_000),
                diagnostics: diagnostics
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
            diagnostics: diagnostics
        )
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
