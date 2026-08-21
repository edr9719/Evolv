import Foundation
import UIKit
import Vision

struct NormalizedCaptureFrame: Equatable {
    var minX: Float
    var minY: Float
    var maxX: Float
    var maxY: Float

    var width: Float { maxX - minX }
    var height: Float { maxY - minY }
}

struct CaptureAcceptanceSignals {
    var poseSpecificTorsoVerified: Bool
    var silhouetteFrame: NormalizedCaptureFrame?
    var orientationClearlyWrong: Bool
    var confirmedExposureIssues: [QualityIssue]
}

enum CaptureAcceptancePolicy {
    struct Result: Equatable {
        var status: CaptureAcceptanceStatus
        var issue: QualityIssue?
        var reasonCode: String?
    }

    static func evaluate(_ signals: CaptureAcceptanceSignals) -> Result {
        if let exposure = signals.confirmedExposureIssues.first {
            return Result(
                status: .rejected,
                issue: exposure,
                reasonCode: exposure == .tooDark
                    ? "confirmed_extreme_darkness"
                    : "confirmed_extreme_overexposure"
            )
        }
        if signals.orientationClearlyWrong {
            return Result(status: .rejected, issue: .poseMismatch, reasonCode: "requested_orientation_mismatch")
        }
        if let frame = signals.silhouetteFrame {
            // Bottom contact is expected for Evolv's head-to-mid-thigh crop.
            // Top and lateral contact indicate meaningful required-area loss.
            if frame.minY <= 0.01 || frame.minX <= 0.005 || frame.maxX >= 0.995 {
                return Result(status: .rejected, issue: .bodyNotFramed, reasonCode: "body_cropped")
            }
            if frame.height < 0.30 || frame.width < 0.06 {
                return Result(status: .rejected, issue: .tooFarAway, reasonCode: "subject_too_small")
            }
            return Result(
                status: signals.poseSpecificTorsoVerified ? .accepted : .provisional,
                issue: nil,
                reasonCode: signals.poseSpecificTorsoVerified ? nil : "silhouette_framing_only"
            )
        }
        if signals.poseSpecificTorsoVerified {
            return Result(status: .accepted, issue: nil, reasonCode: nil)
        }
        return Result(status: .rejected, issue: .insufficientCoverage, reasonCode: "subject_not_detected")
    }
}

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
        async let maskTask = detectedPersonFrame(cgImage: cgImage)
        let (histogram, poseResult, personFrame) = await (histogramTask, poseTask, maskTask)

        var confirmedIssues: [QualityIssue] = []
        // These deliberately identify only nearly unusable exposure. Ordinary
        // shadows and bright backgrounds must not trigger a scary warning.
        if histogram.p90 < 0.16 && histogram.median < 0.10 {
            confirmedIssues.append(.tooDark)
        } else if histogram.p10 > 0.86 && histogram.median > 0.94 {
            confirmedIssues.append(.overexposed)
        }

        let observation: VNHumanBodyPoseObservation?
        if case .success(let detected) = poseResult { observation = detected } else { observation = nil }
        let evidence = observation.map { regionEvidence(from: $0, expectedPose: expectedPose) }
            ?? Dictionary(uniqueKeysWithValues: CaptureRegion.allCases.map {
                ($0, .unavailable("body_landmarks_not_verified"))
            })
        let confidences = evidence.values.map { $0.state == .supported ? Float(1) : Float(0) }
        let coverage = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)

        // This only verifies that the landmarks needed by the pose-specific
        // extractor are visible. It does not grade bodybuilding form.
        let poseLandmarksVerified: Bool = expectedPose == .legs
            ? evidence[.lowerBody]?.state == .supported
            : evidence[.chest]?.state == .supported
                && evidence[.waist]?.state == .supported

        let acceptance = CaptureAcceptancePolicy.evaluate(CaptureAcceptanceSignals(
            poseSpecificTorsoVerified: poseLandmarksVerified,
            silhouetteFrame: personFrame,
            orientationClearlyWrong: observation.map {
                orientationClearlyWrong(observation: $0, expectedPose: expectedPose)
            } ?? false,
            confirmedExposureIssues: confirmedIssues
        ))
        if let issue = acceptance.issue, !confirmedIssues.contains(issue) {
            confirmedIssues.append(issue)
        }

        let status: CaptureVerificationStatus = switch acceptance.status {
        case .accepted, .provisional: .ready
        case .rejected: .reviewRecommended
        }
        let automaticCheckReason = acceptance.reasonCode

        return CaptureAssessment(
            status: status,
            confirmedIssues: confirmedIssues,
            regionEvidence: evidence,
            userOverrodeRecommendation: false,
            brightnessScore: histogram.mean,
            coverageScore: coverage,
            automaticCheckReason: automaticCheckReason,
            captureAcceptance: acceptance.status
        )
    }

    /// Compatibility adapter for version-1 stored analysis.
    static func evaluate(image: UIImage, expectedPose: Pose) async -> QualityGateResult {
        qualityResult(from: await assessWithTimeout(image: image, expectedPose: expectedPose))
    }

    static func qualityResult(from assessment: CaptureAssessment) -> QualityGateResult {
        let issues: [QualityIssue]
        let verdict: QualityVerdict
        if assessment.captureAcceptance == .rejected {
            issues = assessment.confirmedIssues
            verdict = .rejected(issues)
        } else { switch assessment.status {
        case .ready:
            issues = []
            verdict = .pass
        case .reviewRecommended:
            issues = assessment.confirmedIssues
            verdict = .warning(issues)
        case .unavailable:
            issues = [.missingLandmarks]
            verdict = .warning(issues)
        }}

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
            automaticCheckReason: reason,
            captureAcceptance: .provisional
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

    private static func detectedPersonFrame(cgImage: CGImage) async -> NormalizedCaptureFrame? {
        guard let mask = try? await SilhouetteAnalyzer.personMask(cgImage: cgImage),
              mask.width > 0, mask.height > 0 else { return nil }
        return captureFrame(from: mask)
    }

    /// Uses the largest connected foreground component so a detached shadow or
    /// segmentation speck at an image edge cannot falsely turn a usable person
    /// into a cropped-subject rejection.
    static func captureFrame(from mask: BinaryPersonMask) -> NormalizedCaptureFrame? {
        guard mask.width > 0, mask.height > 0 else { return nil }
        var visited = [Bool](repeating: false, count: mask.width * mask.height)
        var largest: (count: Int, minX: Int, minY: Int, maxX: Int, maxY: Int)?
        let neighbors = [
            (-1, -1), (0, -1), (1, -1),
            (-1, 0),             (1, 0),
            (-1, 1),  (0, 1),   (1, 1)
        ]

        for startY in 0..<mask.height {
            for startX in 0..<mask.width {
                let startIndex = startY * mask.width + startX
                guard !visited[startIndex], mask.isForeground(x: startX, y: startY) else {
                    visited[startIndex] = true
                    continue
                }
                var queue = [startIndex]
                visited[startIndex] = true
                var cursor = 0
                var component = (count: 0, minX: startX, minY: startY, maxX: startX, maxY: startY)
                while cursor < queue.count {
                    let index = queue[cursor]
                    cursor += 1
                    let x = index % mask.width
                    let y = index / mask.width
                    component.count += 1
                    component.minX = min(component.minX, x)
                    component.minY = min(component.minY, y)
                    component.maxX = max(component.maxX, x)
                    component.maxY = max(component.maxY, y)
                    for (dx, dy) in neighbors {
                        let nextX = x + dx
                        let nextY = y + dy
                        guard nextX >= 0, nextY >= 0,
                              nextX < mask.width, nextY < mask.height else { continue }
                        let nextIndex = nextY * mask.width + nextX
                        guard !visited[nextIndex] else { continue }
                        visited[nextIndex] = true
                        if mask.isForeground(x: nextX, y: nextY) {
                            queue.append(nextIndex)
                        }
                    }
                }
                if component.count > (largest?.count ?? -1) {
                    largest = component
                }
            }
        }

        guard let largest,
              largest.count >= max(16, mask.width * mask.height / 200) else {
            return nil
        }
        let width = Float(max(mask.width - 1, 1))
        let height = Float(max(mask.height - 1, 1))
        return NormalizedCaptureFrame(
            minX: Float(largest.minX) / width,
            minY: Float(largest.minY) / height,
            maxX: Float(largest.maxX) / width,
            maxY: Float(largest.maxY) / height
        )
    }

    private static func orientationClearlyWrong(
        observation: VNHumanBodyPoseObservation,
        expectedPose: Pose
    ) -> Bool {
        func point(_ joint: VNHumanBodyPoseObservation.JointName) -> VNRecognizedPoint? {
            guard let point = try? observation.recognizedPoint(joint), point.confidence >= 0.45 else { return nil }
            return point
        }
        guard let leftShoulder = point(.leftShoulder), let rightShoulder = point(.rightShoulder),
              let leftHip = point(.leftHip), let rightHip = point(.rightHip) else { return false }
        let shoulderCenter = CGPoint(
            x: (leftShoulder.location.x + rightShoulder.location.x) / 2,
            y: (leftShoulder.location.y + rightShoulder.location.y) / 2
        )
        let hipCenter = CGPoint(
            x: (leftHip.location.x + rightHip.location.x) / 2,
            y: (leftHip.location.y + rightHip.location.y) / 2
        )
        let torso = hypot(shoulderCenter.x - hipCenter.x, shoulderCenter.y - hipCenter.y)
        let span = hypot(
            leftShoulder.location.x - rightShoulder.location.x,
            leftShoulder.location.y - rightShoulder.location.y
        )
        guard torso >= 0.08 else { return false }
        let ratio = span / torso
        let expectsSide = expectedPose == .side || expectedPose == .sideChest
        // Only extreme, high-confidence geometry is rejected. Ambiguous views
        // remain provisional and are decided by downstream comparability.
        return expectsSide ? ratio > 1.15 : ratio < 0.12
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
