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
        guard a.pose == b.pose else { return nil }
        if a.pose == .legs {
            return computeLowerBodyPoseMatchScore(a: a, b: b)
        }
        guard
              torsoFrame(for: a) != nil,
              torsoFrame(for: b) != nil else { return nil }
        let aN = normalize(pose: a)
        let bN = normalize(pose: b)
        let requiredTorso = isSideView(a.pose)
            ? [["leftShoulder", "leftHip"], ["rightShoulder", "rightHip"]]
            : [["leftShoulder", "rightShoulder", "leftHip", "rightHip"]]
        guard requiredTorso.contains(where: { joints in
            joints.allSatisfy { aN.landmark($0) != nil && bN.landmark($0) != nil }
        }) else { return nil }

        let keys: [String]
        if isSideView(a.pose) {
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
        let confidenceFloor: Float = isSideView(a.pose) ? 0.20 : 0.30
        let distances: [Float] = keys.compactMap { key in
            guard let first = aN.landmark(key), let second = bN.landmark(key),
                  first.confidence >= confidenceFloor,
                  second.confidence >= confidenceFloor else { return nil }
            let dx = first.x - second.x
            let dy = first.y - second.y
            return dx * dx + dy * dy
        }
        let minimumCount = isSideView(a.pose) ? 4 : 6
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
        if isSideView(pose.pose) {
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

    private static func computeLowerBodyPoseMatchScore(
        a: ExtractedPose,
        b: ExtractedPose
    ) -> Float? {
        guard let aGeometry = lowerBodyGeometry(for: a),
              let bGeometry = lowerBodyGeometry(for: b) else { return nil }
        let keys = ["leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"]
        let squaredDistances: [Float] = keys.compactMap { key in
            guard let first = aGeometry.landmarks[key],
                  let second = bGeometry.landmarks[key] else { return nil }
            let aPoint = lowerBodyNormalized(first, frame: aGeometry.frame)
            let bPoint = lowerBodyNormalized(second, frame: bGeometry.frame)
            let dx = aPoint.x - bPoint.x
            let dy = aPoint.y - bPoint.y
            return dx * dx + dy * dy
        }
        guard squaredDistances.count == keys.count else { return nil }
        let rms = sqrt(squaredDistances.reduce(0, +) / Float(squaredDistances.count))
        return max(0, min(1, 1 - rms / 0.35))
    }

    private struct LowerBodyGeometry {
        var frame: TorsoFrame
        var landmarks: [String: NormalizedLandmark]
    }

    /// Vision occasionally swaps only its left/right hip labels in a clear
    /// lower-body image. Canonicalize the two observed hips against the two
    /// complete knee/ankle chains before comparing scans. This preserves the
    /// original evidence and still rejects weak or implausible geometry.
    private static func lowerBodyGeometry(for pose: ExtractedPose) -> LowerBodyGeometry? {
        guard let leftHip = pose.landmark("leftHip"),
              let rightHip = pose.landmark("rightHip"),
              leftHip.confidence >= 0.18,
              rightHip.confidence >= 0.18,
              (leftHip.confidence + rightHip.confidence) / 2 >= 0.23,
              let leftKnee = valid(pose.landmark("leftKnee"), minimumConfidence: 0.25),
              let rightKnee = valid(pose.landmark("rightKnee"), minimumConfidence: 0.25),
              let leftAnkle = valid(pose.landmark("leftAnkle"), minimumConfidence: 0.25),
              let rightAnkle = valid(pose.landmark("rightAnkle"), minimumConfidence: 0.25) else { return nil }

        typealias Chain = (
            hip: NormalizedLandmark,
            knee: NormalizedLandmark,
            ankle: NormalizedLandmark
        )
        let direct: [Chain] = [
            (leftHip, leftKnee, leftAnkle),
            (rightHip, rightKnee, rightAnkle)
        ]
        let hipSwapped: [Chain] = [
            (rightHip, leftKnee, leftAnkle),
            (leftHip, rightKnee, rightAnkle)
        ]
        func pairingCost(_ chains: [Chain]) -> Float {
            chains.reduce(0) { total, chain in
                let distalX = chain.ankle.x - chain.knee.x
                let distalY = chain.ankle.y - chain.knee.y
                let distalLength = sqrt(distalX * distalX + distalY * distalY)
                guard distalLength >= 0.02 else { return .greatestFiniteMagnitude }
                let hipX = chain.hip.x - chain.knee.x
                let hipY = chain.hip.y - chain.knee.y
                let lateral = abs(hipX * distalY / distalLength - hipY * distalX / distalLength)
                let fullX = chain.ankle.x - chain.hip.x
                let fullY = chain.ankle.y - chain.hip.y
                let fullLength = sqrt(fullX * fullX + fullY * fullY)
                return total + lateral / max(fullLength, 0.001)
            }
        }
        func plausible(_ chain: Chain) -> Bool {
            let fullX = chain.ankle.x - chain.hip.x
            let fullY = chain.ankle.y - chain.hip.y
            let fullLength = sqrt(fullX * fullX + fullY * fullY)
            guard fullLength >= 0.08 else { return false }
            let alongX = chain.knee.x - chain.hip.x
            let alongY = chain.knee.y - chain.hip.y
            let progress = (alongX * fullX + alongY * fullY) / (fullLength * fullLength)
            let lateral = abs(alongX * fullY - alongY * fullX) / (fullLength * fullLength)
            return progress >= 0.25 && progress <= 0.75 && lateral <= 0.30
        }
        let chains = pairingCost(hipSwapped) < pairingCost(direct) ? hipSwapped : direct
        guard chains.allSatisfy(plausible) else { return nil }

        let canonical: [String: NormalizedLandmark] = [
            "leftHip": chains[0].hip,
            "rightHip": chains[1].hip,
            "leftKnee": leftKnee,
            "rightKnee": rightKnee,
            "leftAnkle": leftAnkle,
            "rightAnkle": rightAnkle
        ]
        let hipX = (chains[0].hip.x + chains[1].hip.x) / 2
        let hipY = (chains[0].hip.y + chains[1].hip.y) / 2
        let ankleX = (leftAnkle.x + rightAnkle.x) / 2
        let ankleY = (leftAnkle.y + rightAnkle.y) / 2
        let downX = ankleX - hipX
        let downY = ankleY - hipY
        let length = sqrt(downX * downX + downY * downY)
        guard length >= 0.08 else { return nil }
        let upX = -downX / length
        let upY = -downY / length
        let frame = TorsoFrame(
            hipX: hipX,
            hipY: hipY,
            upX: upX,
            upY: upY,
            crossX: -upY,
            crossY: upX,
            length: length
        )
        return LowerBodyGeometry(frame: frame, landmarks: canonical)
    }

    private static func lowerBodyNormalized(
        _ landmark: NormalizedLandmark,
        frame: TorsoFrame
    ) -> (x: Float, y: Float) {
        let offsetX = landmark.x - frame.hipX
        let offsetY = landmark.y - frame.hipY
        return (
            (offsetX * frame.crossX + offsetY * frame.crossY) / frame.length,
            (offsetX * frame.upX + offsetY * frame.upY) / frame.length
        )
    }

    private static func isSideView(_ pose: Pose) -> Bool {
        pose == .side || pose == .sideChest
    }
}
