import Foundation
import UIKit
import Vision

/// Conservative, on-device capture verification. A detector failure is recorded
/// as unavailable evidence; it is never converted into a quality accusation.
enum QualityGateEngine {

    static func assessWithTimeout(
        image: UIImage,
        expectedPose: Pose,
        seconds: Double = 5
    ) async -> CaptureAssessment {
        guard seconds > 0 else {
            return unavailableAssessment(reason: "automatic_check_timed_out")
        }
        return await withCheckedContinuation { continuation in
            let gate = AssessmentCompletionGate(continuation: continuation)

            Task {
                let assessment = await assess(image: image, expectedPose: expectedPose)
                gate.finish(assessment)
            }

            Task {
                let nanos = UInt64(max(0, seconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                gate.finish(unavailableAssessment(reason: "automatic_check_timed_out"))
            }
        }
    }

    static func assess(image: UIImage, expectedPose: Pose) async -> CaptureAssessment {
        guard let cgImage = image.cgImage else {
            return unavailableAssessment(reason: "image_decode_failed")
        }

        async let histogramTask = luminanceHistogram(cgImage: cgImage)
        async let poseTask = detectedPoseResult(cgImage: cgImage)
        let (histogram, poseResult) = await (histogramTask, poseTask)

        var confirmedIssues: [QualityIssue] = []
        // These deliberately identify only nearly unusable exposure. Ordinary
        // shadows and bright backgrounds must not trigger a scary warning.
        if histogram.p90 < 0.16 && histogram.median < 0.10 {
            confirmedIssues.append(.tooDark)
        } else if histogram.p10 > 0.86 && histogram.median > 0.94 {
            confirmedIssues.append(.overexposed)
        }

        guard case .success(let observation) = poseResult else {
            var unavailable = unavailableAssessment(reason: "body_landmarks_not_verified")
            unavailable.confirmedIssues = confirmedIssues
            unavailable.status = confirmedIssues.isEmpty ? .unavailable : .reviewRecommended
            unavailable.brightnessScore = histogram.mean
            return unavailable
        }

        let evidence = regionEvidence(from: observation, expectedPose: expectedPose)
        let confidences = evidence.values.map { $0.state == .supported ? Float(1) : Float(0) }
        let coverage = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)

        // This only verifies that the landmarks needed by the pose-specific
        // extractor are visible. It does not grade bodybuilding form.
        let poseLandmarksVerified: Bool = expectedPose == .legs
            ? evidence[.lowerBody]?.state == .supported
            : evidence[.chest]?.state == .supported
                && evidence[.waist]?.state == .supported

        let status: CaptureVerificationStatus
        let automaticCheckReason: String?
        if !confirmedIssues.isEmpty {
            status = .reviewRecommended
            automaticCheckReason = confirmedIssues.contains(.tooDark)
                ? "confirmed_extreme_darkness"
                : "confirmed_extreme_overexposure"
        } else if poseLandmarksVerified {
            status = .ready
            automaticCheckReason = nil
        } else {
            status = .unavailable
            if expectedPose == .legs {
                automaticCheckReason = "lower_body_landmarks_not_verified"
            } else if expectedPose == .side || expectedPose == .sideChest {
                automaticCheckReason = "side_torso_landmarks_not_verified"
            } else {
                automaticCheckReason = "required_torso_landmarks_not_verified"
            }
        }

        return CaptureAssessment(
            status: status,
            confirmedIssues: confirmedIssues,
            regionEvidence: evidence,
            userOverrodeRecommendation: false,
            brightnessScore: histogram.mean,
            coverageScore: coverage,
            automaticCheckReason: automaticCheckReason
        )
    }

    /// Compatibility adapter for version-1 stored analysis.
    static func evaluate(image: UIImage, expectedPose: Pose) async -> QualityGateResult {
        qualityResult(from: await assessWithTimeout(image: image, expectedPose: expectedPose))
    }

    static func qualityResult(from assessment: CaptureAssessment) -> QualityGateResult {
        let issues: [QualityIssue]
        let verdict: QualityVerdict
        switch assessment.status {
        case .ready:
            issues = []
            verdict = .pass
        case .reviewRecommended:
            issues = assessment.confirmedIssues
            verdict = .warning(issues)
        case .unavailable:
            issues = [.missingLandmarks]
            verdict = .warning(issues)
        }

        let regional: [String: Float] = [
            "shoulders": evidenceValue(.shoulders, in: assessment),
            "torso": min(evidenceValue(.chest, in: assessment), evidenceValue(.waist, in: assessment)),
            "arms": evidenceValue(.arms, in: assessment),
            "sideTorso": evidenceValue(.sideTorso, in: assessment)
        ]

        return QualityGateResult(
            verdict: verdict,
            issues: issues,
            blurScore: 0,
            brightnessScore: assessment.brightnessScore,
            coverageScore: assessment.coverageScore,
            regionalCoverage: regional
        )
    }

    static func unavailableAssessment(reason: String) -> CaptureAssessment {
        CaptureAssessment(
            status: .unavailable,
            confirmedIssues: [],
            regionEvidence: Dictionary(uniqueKeysWithValues: CaptureRegion.allCases.map {
                ($0, .unavailable(reason))
            }),
            userOverrodeRecommendation: false,
            brightnessScore: 0.5,
            coverageScore: 0,
            automaticCheckReason: reason
        )
    }

    // MARK: - Evidence

    private static func regionEvidence(
        from observation: VNHumanBodyPoseObservation,
        expectedPose: Pose
    ) -> [CaptureRegion: RegionEvidence] {
        let minimumConfidence: VNConfidence = 0.35
        // Vision's 2D joint confidence is predictably lower when the far-side
        // shoulder and hip overlap the near side. Use a conservative, lower
        // threshold for one complete *same-side* chain instead of requiring
        // independently selected points that may belong to opposite sides.
        let sideMinimumConfidence: VNConfidence = 0.20

        func available(
            _ joint: VNHumanBodyPoseObservation.JointName,
            minimum: VNConfidence
        ) -> Bool {
            guard let point = try? observation.recognizedPoint(joint) else { return false }
            let inset: CGFloat = 0.02
            return point.confidence >= minimum
                && point.location.x >= inset && point.location.x <= 1 - inset
                && point.location.y >= inset && point.location.y <= 1 - inset
        }

        func all(
            _ joints: [VNHumanBodyPoseObservation.JointName],
            minimum: VNConfidence
        ) -> Bool {
            joints.allSatisfy { available($0, minimum: minimum) }
        }

        func oneSideChain() -> Bool {
            all([.leftShoulder, .leftElbow, .leftWrist], minimum: sideMinimumConfidence)
                || all([.rightShoulder, .rightElbow, .rightWrist], minimum: sideMinimumConfidence)
        }

        let isSide = expectedPose == .side || expectedPose == .sideChest
        let leftSideTorso = all([.leftShoulder, .leftHip], minimum: sideMinimumConfidence)
        let rightSideTorso = all([.rightShoulder, .rightHip], minimum: sideMinimumConfidence)
        let sideTorso = leftSideTorso || rightSideTorso
        let shoulders = isSide
            ? sideTorso
            : all([.leftShoulder, .rightShoulder], minimum: minimumConfidence)
        let hips = isSide
            ? sideTorso
            : all([.leftHip, .rightHip], minimum: minimumConfidence)
        let arms = isSide
            ? oneSideChain()
            : all(
                [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist],
                minimum: minimumConfidence
            )
        let torso = shoulders && hips
        let lowerBody = all(
            [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle],
            minimum: 0.25
        )

        func value(_ supported: Bool, _ reason: String) -> RegionEvidence {
            supported ? .supported : .unavailable(reason)
        }

        return [
            .shoulders: value(shoulders, "shoulder_landmarks_not_verified"),
            .chest: value(torso, "upper_torso_not_verified"),
            .waist: value(torso, "waist_not_verified"),
            .arms: value(arms, "full_arms_not_verified"),
            .sideTorso: value(isSide && sideTorso, isSide ? "side_torso_not_verified" : "not_applicable"),
            .lowerBody: value(expectedPose == .legs && lowerBody, expectedPose == .legs ? "lower_body_not_verified" : "not_applicable")
        ]
    }

    private static func evidenceValue(_ region: CaptureRegion, in assessment: CaptureAssessment) -> Float {
        assessment.regionEvidence[region]?.state == .supported ? 1 : 0
    }

    // MARK: - Vision

    private static func detectedPoseResult(
        cgImage: CGImage
    ) async -> Result<VNHumanBodyPoseObservation, Error> {
        await Task.detached(priority: .userInitiated) {
            do {
                let request = VNDetectHumanBodyPoseRequest()
                request.revision = BodyPoseExtractor.bodyPoseRevision
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                try handler.perform([request])
                guard let observation = request.results?.first else {
                    throw AssessmentError.noBodyObservation
                }
                return .success(observation)
            } catch {
                return .failure(error)
            }
        }.value
    }

    // MARK: - Exposure

    private struct LuminanceHistogram {
        let p10: Float
        let median: Float
        let p90: Float
        let mean: Float
    }

    private static func luminanceHistogram(cgImage: CGImage) async -> LuminanceHistogram {
        await Task.detached(priority: .utility) {
            let width = 64
            let height = 64
            var pixels = [UInt8](repeating: 0, count: width * height)
            guard let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return LuminanceHistogram(p10: 0.5, median: 0.5, p90: 0.5, mean: 0.5)
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            pixels.sort()

            func percentile(_ value: Double) -> Float {
                let index = min(pixels.count - 1, max(0, Int(Double(pixels.count - 1) * value)))
                return Float(pixels[index]) / 255
            }

            let mean = pixels.reduce(Float(0)) { $0 + Float($1) } / Float(pixels.count) / 255
            return LuminanceHistogram(
                p10: percentile(0.10),
                median: percentile(0.50),
                p90: percentile(0.90),
                mean: mean
            )
        }.value
    }

    private enum AssessmentError: Error {
        case noBodyObservation
    }
}

/// CheckedContinuation has no built-in "resume first" primitive. This small
/// lock-protected gate lets either Vision or the timeout win without a double resume.
private final class AssessmentCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CaptureAssessment, Never>?

    init(continuation: CheckedContinuation<CaptureAssessment, Never>) {
        self.continuation = continuation
    }

    func finish(_ assessment: CaptureAssessment) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: assessment)
    }
}
