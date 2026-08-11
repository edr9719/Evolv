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
        var failures: [String: String]
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

        let baseline = await process(
            scan: anchor,
            baseline: nil,
            loadPhoto: loadPhoto
        )
        var results: [Int: ValidationSetComparison] = [:]

        for record in session.sets.sorted(by: { $0.setNumber < $1.setNumber }) where record.setNumber > 1 {
            let comparisonStartedAt = Date()
            guard let scan = scansByID[record.scanID] else {
                results[record.setNumber] = ValidationSetComparison(
                    setNumber: record.setNumber,
                    regionalComparisons: [],
                    failures: ["scan": "scan_missing"],
                    hasSufficientCoreEvidence: false,
                    processingDurationMilliseconds: Int(Date().timeIntervalSince(comparisonStartedAt) * 1_000)
                )
                continue
            }
            let current = await process(
                scan: scan,
                baseline: baseline,
                loadPhoto: loadPhoto
            )
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
            var failures = baseline.failures
            current.failures.forEach { failures[$0.key] = $0.value }
            results[record.setNumber] = ValidationSetComparison(
                setNumber: record.setNumber,
                regionalComparisons: comparisons,
                failures: failures,
                hasSufficientCoreEvidence: coreRegions.isSubset(of: supportedCore),
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

    /// Kept separate from Vision so the safety semantics can be exhaustively
    /// unit-tested. A processing failure is reviewable rather than silently
    /// downgraded to a clean result; missing supported regions without an
    /// explicit pipeline failure remains limited evidence.
    static func classify(
        session: ValidationStudySession,
        comparisonsBySet results: [Int: ValidationSetComparison]
    ) -> ValidationConsistencyStatus {
        let hasDeviation = session.statusReasons.isEmpty == false
            || session.sets.contains { record in
                guard let conditions = record.conditions else { return true }
                return !conditions.stayedTheSame || !conditions.deviations.isEmpty
            }
        let hasProcessingFailure = results.values.contains { !$0.failures.isEmpty }
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

        if hasDeviation || hasProcessingFailure || hasUnexpectedSignal {
            return .needsReview
        }
        return sufficientCoreEveryTime ? .consistent : .limitedEvidence
    }

    private static func process(
        scan: Scan,
        baseline: ProcessedScan?,
        loadPhoto: @escaping (String) -> UIImage?
    ) async -> ProcessedScan {
        var extracted: [ExtractedPose] = []
        var profiles: [SilhouetteProfile] = []
        var failures: [String: String] = [:]
        let cameraMetadata = Dictionary(uniqueKeysWithValues: scan.standardCaptures.compactMap { capture in
            capture.cameraMetadata.map { (capture.pose, $0) }
        })

        for pose in Pose.required {
            guard let capture = scan.capture(for: pose),
                  let image = loadPhoto(capture.imageFilename) else {
                failures[pose.rawValue] = "photo_load_failed"
                continue
            }
            let prepared = PhotoStore.prepare(image).image
            do {
                var bodyPose = try await BodyPoseExtractor.extract(
                    from: prepared,
                    pose: pose,
                    scanId: scan.id
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
                    failures["\(pose.rawValue)_silhouette"] = "silhouette_processing_failed"
                }
            } catch {
                failures[pose.rawValue] = "pose_extraction_failed"
            }
        }

        return ProcessedScan(
            extractedPoses: extracted,
            profiles: profiles,
            cameraMetadata: cameraMetadata,
            failures: failures
        )
    }
}
