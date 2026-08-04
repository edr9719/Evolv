import UIKit
import Vision
import Accelerate

/// Runs quality checks on a captured image before it is saved.
/// Uses on-device Vision and image processing only — no network calls.
enum QualityGateEngine {

    // MARK: - Public API

    static func evaluate(image: UIImage, expectedPose: Pose) async -> QualityGateResult {
        guard let cgImage = image.cgImage else {
            return QualityGateResult(
                verdict: .warning([.missingLandmarks]),
                issues: [.missingLandmarks],
                blurScore: 0, brightnessScore: 0, coverageScore: 0, regionalCoverage: [:]
            )
        }

        // Run Vision body pose and segmentation in parallel
        async let poseResult = detectBodyPose(cgImage: cgImage)
        async let blur = computeBlurScore(cgImage: cgImage)
        async let brightness = computeBrightness(cgImage: cgImage)

        let (obs, blurScore, brightScore) = await (poseResult, blur, brightness)

        var issues: [QualityIssue] = []

        // Lighting checks
        if brightScore < 0.12 { issues.append(.tooDark) }
        if brightScore > 0.94 { issues.append(.overexposed) }
        if blurScore < 60     { issues.append(.blurry) }

        // Coverage computation — fall through gracefully when Vision finds no body
        let coverageScore: Float
        let regionalCoverage: [String: Float]
        if let observation = obs {
            (coverageScore, regionalCoverage) = computeCoverage(from: observation, framing: expectedPose.framing)

            // Relaxed thresholds: typical waist-up selfies score ~0.40–0.55 on fullBody framing.
            // We warn rather than block so users can always proceed.
            let insufficientThreshold: Float
            let partialThreshold: Float
            switch expectedPose.framing {
            case .fullBody:
                insufficientThreshold = 0.20
                partialThreshold = 0.40
            case .torsoUp, .legsOnly:
                insufficientThreshold = 0.15
                partialThreshold = 0.30
            }
            if coverageScore < insufficientThreshold {
                issues.append(.insufficientCoverage)
            } else if coverageScore < partialThreshold {
                issues.append(.partialCoverage)
            }

            // Distance heuristic — if shoulder span relative to image width is too small, too far
            let shoulderSpan = shoulderSpanRatio(from: observation)
            if shoulderSpan < 0.06 { issues.append(.tooFarAway) }
        } else {
            // Vision couldn't detect a body — give advice but never hard-block
            coverageScore = 0
            regionalCoverage = [:]
            issues.append(.missingLandmarks)
        }

        // Mirror selfie detection
        if detectMirrorSelfie(cgImage: cgImage) { issues.append(.mirrorSelfieDetected) }

        // All issues are advisory — users can always "Use Anyway". No hard blocks.
        let verdict: QualityVerdict
        if issues.isEmpty {
            verdict = .pass
        } else {
            verdict = .warning(issues)
        }

        return QualityGateResult(
            verdict: verdict,
            issues: issues,
            blurScore: blurScore,
            brightnessScore: brightScore,
            coverageScore: coverageScore,
            regionalCoverage: regionalCoverage
        )
    }

    // MARK: - Vision

    private static func detectBodyPose(cgImage: CGImage) async -> VNHumanBodyPoseObservation? {
        return await withCheckedContinuation { continuation in
            let request = VNDetectHumanBodyPoseRequest { request, _ in
                let obs = request.results?.first as? VNHumanBodyPoseObservation
                continuation.resume(returning: obs)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Coverage Score

    /// Coverage score 0–1 from weighted landmark confidence.
    /// Weights are framing-aware: torso-up shots aren't penalized for missing legs,
    /// and legs-only shots aren't penalized for missing head/shoulders.
    private static func computeCoverage(
        from obs: VNHumanBodyPoseObservation,
        framing: Pose.Framing = .fullBody
    ) -> (coverage: Float, regional: [String: Float]) {
        let regionWeights: [(joints: [VNHumanBodyPoseObservation.JointName], name: String, weight: Float)] = {
            switch framing {
            case .fullBody:
                return [
                    ([.nose], "head", 0.10),
                    ([.leftShoulder, .rightShoulder], "shoulders", 0.15),
                    ([.leftElbow, .rightElbow, .leftWrist, .rightWrist], "arms", 0.15),
                    ([.leftHip, .rightHip], "torso", 0.25),
                    ([.leftKnee, .rightKnee], "thighs", 0.20),
                    ([.leftAnkle, .rightAnkle], "legs", 0.15)
                ]
            case .torsoUp:
                // Head/shoulders/arms/torso carry the score. Knees/ankles optional.
                return [
                    ([.nose], "head", 0.15),
                    ([.leftShoulder, .rightShoulder], "shoulders", 0.30),
                    ([.leftElbow, .rightElbow, .leftWrist, .rightWrist], "arms", 0.20),
                    ([.leftHip, .rightHip], "torso", 0.35)
                ]
            case .legsOnly:
                return [
                    ([.leftHip, .rightHip], "hips", 0.35),
                    ([.leftKnee, .rightKnee], "thighs", 0.35),
                    ([.leftAnkle, .rightAnkle], "ankles", 0.30)
                ]
            }
        }()

        var total: Float = 0
        var regional: [String: Float] = [:]

        for region in regionWeights {
            let avg = region.joints.compactMap {
                try? obs.recognizedPoint($0)
            }.map { Float($0.confidence) }.reduce(0, +)
            let regionScore = region.joints.isEmpty ? 0 : avg / Float(region.joints.count)
            regional[region.name] = regionScore
            total += regionScore * region.weight
        }

        return (total, regional)
    }

    // MARK: - Shoulder Span

    private static func shoulderSpanRatio(from obs: VNHumanBodyPoseObservation) -> CGFloat {
        guard let ls = try? obs.recognizedPoint(.leftShoulder),
              let rs = try? obs.recognizedPoint(.rightShoulder),
              ls.confidence > 0.3, rs.confidence > 0.3 else { return 0.15 }
        return abs(ls.location.x - rs.location.x)
    }

    // MARK: - Blur (Laplacian variance)

    /// Higher = sharper. Threshold: < 80 = blurry.
    private static func computeBlurScore(cgImage: CGImage) async -> Float {
        return await Task.detached(priority: .utility) {
            // Resize to 64x64 for speed
            let size = CGSize(width: 64, height: 64)
            let ctx = CGContext(
                data: nil, width: 64, height: 64,
                bitsPerComponent: 8, bytesPerRow: 64,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
            ctx?.draw(cgImage, in: CGRect(origin: .zero, size: size))
            guard let drawn = ctx?.makeImage() else { return Float(0) }

            let pxCount = 64 * 64
            var pixels = [UInt8](repeating: 0, count: pxCount)
            guard let dataCtx = CGContext(
                data: &pixels, width: 64, height: 64,
                bitsPerComponent: 8, bytesPerRow: 64,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return Float(0) }
            dataCtx.draw(drawn, in: CGRect(origin: .zero, size: size))

            // Compute Laplacian variance
            let floatPixels = pixels.map { Float($0) }
            var laplacianSum: Float = 0
            for y in 1..<63 {
                for x in 1..<63 {
                    let idx = y * 64 + x
                    let lap = floatPixels[idx-64] + floatPixels[idx+64]
                                + floatPixels[idx-1] + floatPixels[idx+1]
                                - 4 * floatPixels[idx]
                    laplacianSum += lap * lap
                }
            }
            let variance = laplacianSum / Float(62 * 62)
            return variance
        }.value
    }

    // MARK: - Brightness

    private static func computeBrightness(cgImage: CGImage) async -> Float {
        return await Task.detached(priority: .utility) {
            let w = 32, h = 32
            var pixels = [UInt8](repeating: 0, count: w * h)
            guard let ctx = CGContext(
                data: &pixels, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return Float(0.5) }
            ctx.draw(cgImage, in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))
            let avg = pixels.map { Float($0) }.reduce(0, +) / Float(pixels.count)
            return avg / 255.0
        }.value
    }

    // MARK: - Mirror Selfie Heuristic

    /// Detects a bright vertical column near center that suggests a bathroom mirror.
    private static func detectMirrorSelfie(cgImage: CGImage) -> Bool {
        let w = 16, h = 32
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return false }
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: CGSize(width: w, height: h)))

        // Check if center column (col 7–8) is significantly brighter than edges
        let centerBrightness = (0..<h).map { Float(pixels[$0 * w + 7]) + Float(pixels[$0 * w + 8]) }
            .reduce(0, +) / Float(h * 2)
        let edgeBrightness = (0..<h).map { Float(pixels[$0 * w + 0]) + Float(pixels[$0 * w + w-1]) }
            .reduce(0, +) / Float(h * 2)
        return centerBrightness > edgeBrightness * 1.5 && centerBrightness > 200
    }

}
