import Foundation

/// Normalizes pose landmarks to a standard height and corrects tilt for consistent delta computation.
enum NormalizationEngine {

    static let referenceHeight: Float = 400.0

    // MARK: - Normalize

    /// Scales landmarks to referenceHeight, translates hip midpoint to (0,0), then de-rotates tilt.
    static func normalize(pose: ExtractedPose) -> ExtractedPose {
        var landmarks = pose.landmarks
        guard !landmarks.isEmpty else { return pose }

        let scale = referenceHeight / max(pose.bodyHeightPx, 1.0)

        // Scale
        landmarks = landmarks.map {
            NormalizedLandmark(joint: $0.joint, x: $0.x * scale, y: $0.y * scale, confidence: $0.confidence)
        }

        // Translate: move hip midpoint to origin
        let hipMidX = midX(landmarks: landmarks, j1: "leftHip", j2: "rightHip") ?? 0
        let hipMidY = midY(landmarks: landmarks, j1: "leftHip", j2: "rightHip") ?? 0

        landmarks = landmarks.map {
            NormalizedLandmark(joint: $0.joint, x: $0.x - hipMidX, y: $0.y - hipMidY, confidence: $0.confidence)
        }

        // Compute tilt from shoulder and hip horizontal angles, average them
        let shoulderTilt = computeTilt(landmarks: landmarks, j1: "leftShoulder", j2: "rightShoulder")
        let hipTilt      = computeTilt(landmarks: landmarks, j1: "leftHip",      j2: "rightHip")
        let avgTilt      = (shoulderTilt + hipTilt) / 2.0

        // De-rotate if tilt is meaningful (> 1°)
        if abs(avgTilt) > 0.0175 {
            landmarks = rotateBy(-avgTilt, landmarks: landmarks)
        }

        var result = pose
        result.landmarks = landmarks
        return result
    }

    // MARK: - Pose Match Score (normalized space)

    static func computePoseMatchScore(a: ExtractedPose, b: ExtractedPose) -> Float {
        let aN = normalize(pose: a)
        let bN = normalize(pose: b)

        let keyPairs = [
            ("leftShoulder", "rightShoulder"),
            ("leftHip", "rightHip"),
            ("leftElbow", "leftWrist"),
            ("rightElbow", "rightWrist"),
            ("leftShoulder", "leftHip"),
            ("rightShoulder", "rightHip"),
            ("leftHip", "leftKnee"),
            ("rightHip", "rightKnee")
        ]

        var totalDiff: Float = 0
        var count = 0

        for (j1, j2) in keyPairs {
            guard let a1 = aN.landmark(j1), let a2 = aN.landmark(j2),
                  let b1 = bN.landmark(j1), let b2 = bN.landmark(j2) else { continue }
            let aDist = dist(a1, a2)
            let bDist = dist(b1, b2)
            totalDiff += abs(aDist - bDist)
            count += 1
        }

        guard count > 0 else { return 0.5 }
        let avgDiff = totalDiff / Float(count)
        return max(0, 1.0 - avgDiff / 30.0)
    }

    // MARK: - Private

    private static func computeTilt(landmarks: [NormalizedLandmark], j1: String, j2: String) -> Float {
        guard let l = landmarks.landmark(j1), let r = landmarks.landmark(j2) else { return 0 }
        return atan2(r.y - l.y, r.x - l.x)
    }

    private static func rotateBy(_ angle: Float, landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        let cos = Foundation.cos(angle), sin = Foundation.sin(angle)
        return landmarks.map {
            let rx = $0.x * cos - $0.y * sin
            let ry = $0.x * sin + $0.y * cos
            return NormalizedLandmark(joint: $0.joint, x: rx, y: ry, confidence: $0.confidence)
        }
    }

    private static func midX(landmarks: [NormalizedLandmark], j1: String, j2: String) -> Float? {
        guard let l = landmarks.landmark(j1), let r = landmarks.landmark(j2) else { return nil }
        return (l.x + r.x) / 2
    }

    private static func midY(landmarks: [NormalizedLandmark], j1: String, j2: String) -> Float? {
        guard let l = landmarks.landmark(j1), let r = landmarks.landmark(j2) else { return nil }
        return (l.y + r.y) / 2
    }

    private static func dist(_ a: NormalizedLandmark, _ b: NormalizedLandmark) -> Float {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}
