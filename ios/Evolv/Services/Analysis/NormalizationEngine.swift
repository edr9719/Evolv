import Foundation

/// Produces a person-aligned landmark frame for pose comparability only.
/// Silhouette sampling always uses the original image-space landmarks.
enum NormalizationEngine {
    static func normalize(pose: ExtractedPose) -> ExtractedPose {
        guard let frame = torsoFrame(for: pose) else { return pose }
        var result = pose
        result.landmarks = pose.landmarks.map { landmark in
            let offsetX = landmark.x - frame.hipX
            let offsetY = landmark.y - frame.hipY
            return NormalizedLandmark(
                joint: landmark.joint,
                x: (offsetX * frame.crossX + offsetY * frame.crossY) / frame.length,
                y: (offsetX * frame.upX + offsetY * frame.upY) / frame.length,
                confidence: landmark.confidence
            )
        }
        return result
    }

    /// Returns nil when the two records do not contain enough comparable body
    /// geometry. A score of 0.85 corresponds to roughly 5% of torso length RMS
    /// landmark displacement after translation, scale and roll normalization.
    static func computePoseMatchScore(a: ExtractedPose, b: ExtractedPose) -> Float? {
        guard a.pose == b.pose,
              torsoFrame(for: a) != nil,
              torsoFrame(for: b) != nil else { return nil }
        let aN = normalize(pose: a)
        let bN = normalize(pose: b)
        let requiredTorso = a.pose == .side
            ? [["leftShoulder", "leftHip"], ["rightShoulder", "rightHip"]]
            : [["leftShoulder", "rightShoulder", "leftHip", "rightHip"]]
        guard requiredTorso.contains(where: { joints in
            joints.allSatisfy { aN.landmark($0) != nil && bN.landmark($0) != nil }
        }) else { return nil }

        let keys: [String]
        if a.pose == .side {
            let sides = ["left", "right"]
            let sharedCandidates: [(keys: [String], score: Float)] = sides.compactMap { side in
                let candidate = ["\(side)Shoulder", "\(side)Hip", "\(side)Elbow", "\(side)Wrist"]
                let pairs = candidate.compactMap { key -> (NormalizedLandmark, NormalizedLandmark)? in
                    guard let first = aN.landmark(key), let second = bN.landmark(key),
                          first.confidence >= 0.20, second.confidence >= 0.20 else { return nil }
                    return (first, second)
                }
                guard pairs.count == candidate.count else { return nil }
                let confidence = pairs.map { min($0.0.confidence, $0.1.confidence) }.reduce(0, +)
                return (candidate, confidence)
            }
            guard let strongest = sharedCandidates.max(by: { $0.score < $1.score }) else { return nil }
            keys = strongest.keys
        } else {
            keys = [
                "leftShoulder", "rightShoulder", "leftHip", "rightHip",
                "leftElbow", "rightElbow", "leftWrist", "rightWrist"
            ]
        }
        let confidenceFloor: Float = a.pose == .side ? 0.20 : 0.30
        let distances: [Float] = keys.compactMap { key in
            guard let first = aN.landmark(key), let second = bN.landmark(key),
                  first.confidence >= confidenceFloor,
                  second.confidence >= confidenceFloor else { return nil }
            let dx = first.x - second.x
            let dy = first.y - second.y
            return dx * dx + dy * dy
        }
        let minimumCount = a.pose == .side ? 4 : 6
        guard distances.count >= minimumCount else { return nil }
        let rms = sqrt(distances.reduce(0, +) / Float(distances.count))
        return max(0, min(1, 1 - rms / 0.35))
    }

    private struct TorsoFrame {
        var hipX: Float
        var hipY: Float
        var upX: Float
        var upY: Float
        var crossX: Float
        var crossY: Float
        var length: Float
    }

    private static func torsoFrame(for pose: ExtractedPose) -> TorsoFrame? {
        let chain: (NormalizedLandmark, NormalizedLandmark)?
        if pose.pose == .side {
            let candidates = ["left", "right"].compactMap { side -> (NormalizedLandmark, NormalizedLandmark, Float)? in
                guard let shoulder = valid(pose.landmark("\(side)Shoulder"), minimumConfidence: 0.20),
                      let hip = valid(pose.landmark("\(side)Hip"), minimumConfidence: 0.20) else { return nil }
                let hasCompleteArm = valid(pose.landmark("\(side)Elbow"), minimumConfidence: 0.20) != nil
                    && valid(pose.landmark("\(side)Wrist"), minimumConfidence: 0.20) != nil
                return (shoulder, hip, min(shoulder.confidence, hip.confidence) + (hasCompleteArm ? 1 : 0))
            }
            chain = candidates.max { first, second in
                first.2 < second.2
            }.map { ($0.0, $0.1) }
        } else if let leftShoulder = valid(pose.landmark("leftShoulder")),
                  let rightShoulder = valid(pose.landmark("rightShoulder")),
                  let leftHip = valid(pose.landmark("leftHip")),
                  let rightHip = valid(pose.landmark("rightHip")) {
            chain = (
                NormalizedLandmark(
                    joint: "shoulderMid",
                    x: (leftShoulder.x + rightShoulder.x) / 2,
                    y: (leftShoulder.y + rightShoulder.y) / 2,
                    confidence: min(leftShoulder.confidence, rightShoulder.confidence)
                ),
                NormalizedLandmark(
                    joint: "hipMid",
                    x: (leftHip.x + rightHip.x) / 2,
                    y: (leftHip.y + rightHip.y) / 2,
                    confidence: min(leftHip.confidence, rightHip.confidence)
                )
            )
        } else {
            chain = nil
        }
        guard let (shoulder, hip) = chain else { return nil }
        let dx = shoulder.x - hip.x
        let dy = shoulder.y - hip.y
        let length = sqrt(dx * dx + dy * dy)
        guard length >= 0.04 else { return nil }
        let upX = dx / length
        let upY = dy / length
        return TorsoFrame(
            hipX: hip.x,
            hipY: hip.y,
            upX: upX,
            upY: upY,
            crossX: -upY,
            crossY: upX,
            length: length
        )
    }

    private static func valid(
        _ landmark: NormalizedLandmark?,
        minimumConfidence: Float = 0.30
    ) -> NormalizedLandmark? {
        guard let landmark, landmark.confidence >= minimumConfidence else { return nil }
        return landmark
    }
}
