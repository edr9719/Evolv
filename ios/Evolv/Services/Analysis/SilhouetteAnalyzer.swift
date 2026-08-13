import UIKit
import Vision

/// A value-type person mask that can cross task boundaries and be exercised by
/// deterministic fixture tests without invoking Vision.
struct BinaryPersonMask {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func isForeground(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        let index = y * width + x
        guard index < pixels.count else { return false }
        return pixels[index] > 128
    }
}

struct AnalysisPoint {
    var x: Float
    var y: Float

    static func + (lhs: AnalysisPoint, rhs: AnalysisPoint) -> AnalysisPoint {
        AnalysisPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: AnalysisPoint, rhs: AnalysisPoint) -> AnalysisPoint {
        AnalysisPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: AnalysisPoint, rhs: Float) -> AnalysisPoint {
        AnalysisPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    var length: Float { sqrt(x * x + y * y) }
    var normalized: AnalysisPoint {
        let length = max(length, 0.0001)
        return AnalysisPoint(x: x / length, y: y / length)
    }
}

struct PersonCoordinateSystem {
    let shoulderCenter: AnalysisPoint
    let hipCenter: AnalysisPoint
    let downAxis: AnalysisPoint
    let crossAxis: AnalysisPoint
    let torsoLength: Float

    func point(down fraction: Float) -> AnalysisPoint {
        shoulderCenter + downAxis * (torsoLength * fraction)
    }
}

struct SilhouetteSamplingLine: Codable {
    var label: String
    var startX: Float
    var startY: Float
    var endX: Float
    var endY: Float
}

struct SilhouetteDebugArtifact {
    var mask: BinaryPersonMask
    var samplingLines: [SilhouetteSamplingLine]
}

/// Extracts person-aligned torso and limb thickness from a segmentation mask.
/// Every value is normalized by shoulder-to-hip length, so uniform image scale,
/// translation, and small camera roll do not become body-change signals.
enum SilhouetteAnalyzer {
    static let personSegmentationRevision = VNGeneratePersonSegmentationRequestRevision1
    static let segmentationQualityIdentifier = "accurate"
    private static let minimumLandmarkConfidence: Float = 0.30
    // Exact profile views naturally overlap left/right joints, which lowers
    // Vision's per-joint confidence even when one complete torso chain exists.
    // Keep requiring observed landmarks, but use a separately tested floor for
    // the visible shoulder-to-hip chain instead of rejecting valid side poses.
    private static let minimumSideLandmarkConfidence: Float = 0.20
    // Shorts and the upper-body crop boundary make hip joints less certain in
    // otherwise clear legs photos. Accept one moderately uncertain hip only
    // when both complete distal chains exist, the average hip evidence clears
    // a stronger floor, and the knee lies plausibly between hip and ankle.
    private static let minimumLegHipConfidence: Float = 0.18
    private static let minimumAverageLegHipConfidence: Float = 0.23
    private static let minimumLegDistalConfidence: Float = 0.25

    static func analyze(image: UIImage, extractedPose: ExtractedPose) async throws -> SilhouetteProfile {
        try await analyzeWithDebug(image: image, extractedPose: extractedPose).profile
    }

    static func analyzeWithDebug(
        image: UIImage,
        extractedPose: ExtractedPose
    ) async throws -> (profile: SilhouetteProfile, debug: SilhouetteDebugArtifact) {
        guard let cgImage = image.cgImage else { throw AnalysisError.noImage }
        let mask = try await personMask(cgImage: cgImage)
        let profile = try analyze(mask: mask, extractedPose: extractedPose)
        return (
            profile,
            SilhouetteDebugArtifact(
                mask: mask,
                samplingLines: debugSamplingLines(mask: mask, pose: extractedPose)
            )
        )
    }

    /// Internal fixture seam used by physical-device and synthetic-mask tests.
    static func analyze(mask: BinaryPersonMask, extractedPose: ExtractedPose) throws -> SilhouetteProfile {
        if extractedPose.pose == .legs {
            return try analyzeLegs(mask: mask, extractedPose: extractedPose)
        }
        let coordinates = try coordinateSystem(mask: mask, pose: extractedPose)
        let torsoLimit = max(4, Int((coordinates.torsoLength * 0.9).rounded()))

        func torsoFeature(_ region: BodyRegion, fraction: Float) -> PoseRegionFeature? {
            let thicknesses = [Float(-0.02), -0.01, 0, 0.01, 0.02].compactMap { offset in
                contiguousThickness(
                    mask: mask,
                    center: coordinates.point(down: fraction + offset),
                    axis: coordinates.crossAxis,
                    maximumDistance: torsoLimit
                )
            }
            guard thicknesses.count >= 3 else { return nil }
            let thickness = median(thicknesses)
            return PoseRegionFeature(
                pose: extractedPose.pose,
                region: region,
                normalizedValue: thickness / coordinates.torsoLength,
                source: .torsoCrossSection,
                evidenceReason: nil
            )
        }

        var features: [PoseRegionFeature] = []
        if supportsShoulderFeature(extractedPose.pose),
           let shoulders = torsoFeature(.shoulders, fraction: 0.08) {
            features.append(shoulders)
        }
        if supportsChestFeature(extractedPose.pose),
           let chest = torsoFeature(.chest, fraction: 0.45) {
            features.append(chest)
        }
        if let waist = torsoFeature(.waist, fraction: 0.78) {
            features.append(waist)
        }
        if let arms = armFeature(mask: mask, pose: extractedPose, coordinates: coordinates) {
            features.append(arms)
        }

        guard !features.isEmpty else { throw AnalysisError.insufficientEvidence }
        let shoulder = features.first { $0.region == .shoulders }?.normalizedValue ?? 0
        let chest = features.first { $0.region == .chest }?.normalizedValue ?? 0
        let waist = features.first { $0.region == .waist }?.normalizedValue ?? 0
        let arms = features.first { $0.region == .arms }?.normalizedValue ?? 0
        let taper = shoulder > 0 ? (shoulder - waist) / shoulder : 0

        return SilhouetteProfile(
            scanId: extractedPose.scanId,
            pose: extractedPose.pose,
            widthAtY: horizontalDebugProfile(mask),
            shoulderWidthRatio: shoulder,
            chestWidthRatio: chest,
            waistWidthRatio: waist,
            armMidWidthRatio: arms,
            thighMidWidthRatio: 0,
            taperIndex: taper,
            chestToWaistRatio: waist > 0 ? chest / waist : 1,
            shoulderToWaistRatio: waist > 0 ? shoulder / waist : 1,
            hipWidthRatio: nil,
            lowerTorsoWidthRatio: waist,
            supportedRegions: features.map(\.region),
            regionFeatures: features,
            torsoReferencePixels: coordinates.torsoLength,
            poseMatchScore: extractedPose.poseMatchScore
        )
    }

    /// Legs use a lower-body reference because the requested crop deliberately
    /// excludes shoulders. Thickness is sampled perpendicular to each
    /// hip-to-knee axis and normalized by hip-to-ankle length.
    private static func analyzeLegs(
        mask: BinaryPersonMask,
        extractedPose: ExtractedPose
    ) throws -> SilhouetteProfile {
        func point(_ joint: String, minimumConfidence: Float) -> AnalysisPoint? {
            imagePoint(
                extractedPose.landmark(joint),
                mask: mask,
                minimumConfidence: minimumConfidence
            )
        }
        guard let leftHipLandmark = extractedPose.landmark("leftHip"),
              let rightHipLandmark = extractedPose.landmark("rightHip"),
              leftHipLandmark.confidence >= minimumLegHipConfidence,
              rightHipLandmark.confidence >= minimumLegHipConfidence,
              (leftHipLandmark.confidence + rightHipLandmark.confidence) / 2 >= minimumAverageLegHipConfidence,
              let leftHip = point("leftHip", minimumConfidence: minimumLegHipConfidence),
              let leftKnee = point("leftKnee", minimumConfidence: minimumLegDistalConfidence),
              let leftAnkle = point("leftAnkle", minimumConfidence: minimumLegDistalConfidence),
              let rightHip = point("rightHip", minimumConfidence: minimumLegHipConfidence),
              let rightKnee = point("rightKnee", minimumConfidence: minimumLegDistalConfidence),
              let rightAnkle = point("rightAnkle", minimumConfidence: minimumLegDistalConfidence) else {
            throw AnalysisError.insufficientLandmarks
        }

        func isPlausibleLegChain(hip: AnalysisPoint, knee: AnalysisPoint, ankle: AnalysisPoint) -> Bool {
            let full = ankle - hip
            guard full.length >= 20 else { return false }
            let along = knee - hip
            let progress = (along.x * full.normalized.x + along.y * full.normalized.y) / full.length
            let lateral = abs(along.x * full.normalized.y - along.y * full.normalized.x) / full.length
            return progress >= 0.25 && progress <= 0.75 && lateral <= 0.30
        }
        typealias LegChain = (hip: AnalysisPoint, knee: AnalysisPoint, ankle: AnalysisPoint)
        let direct: [LegChain] = [
            (leftHip, leftKnee, leftAnkle),
            (rightHip, rightKnee, rightAnkle)
        ]
        let hipSwapped: [LegChain] = [
            (rightHip, leftKnee, leftAnkle),
            (leftHip, rightKnee, rightAnkle)
        ]
        func pairingCost(_ chains: [LegChain]) -> Float {
            chains.reduce(0) { total, chain in
                let distal = chain.ankle - chain.knee
                guard distal.length >= 8 else { return .greatestFiniteMagnitude }
                let hipOffset = chain.hip - chain.knee
                let lateral = abs(
                    hipOffset.x * distal.normalized.y -
                    hipOffset.y * distal.normalized.x
                )
                return total + lateral / max((chain.ankle - chain.hip).length, 1)
            }
        }
        // Vision can swap left/right hip labels while keeping each knee/ankle
        // chain internally consistent. Choose the one-to-one hip assignment
        // closest to those observed distal axes; never manufacture a point.
        let chains = pairingCost(hipSwapped) < pairingCost(direct) ? hipSwapped : direct
        guard chains.allSatisfy({ chain in
            isPlausibleLegChain(hip: chain.hip, knee: chain.knee, ankle: chain.ankle)
        }) else {
            throw AnalysisError.insufficientLandmarks
        }

        let referenceLengths = chains.map { ($0.ankle - $0.hip).length }
            .filter { $0 >= 20 }
        guard referenceLengths.count == 2 else { throw AnalysisError.invalidReferenceScale }
        let reference = median(referenceLengths)

        func thighThickness(hip: AnalysisPoint, knee: AnalysisPoint) -> Float? {
            let segment = knee - hip
            guard segment.length >= 10 else { return nil }
            let perpendicular = AnalysisPoint(x: -segment.normalized.y, y: segment.normalized.x)
            let maximum = max(3, Int((reference * 0.20).rounded()))
            // Avoid the proximal hip/shorts area, where the two thighs often
            // form one contiguous mask segment. Mid-distal samples preserve
            // isolated, same-leg evidence without treating the pelvis or the
            // opposite thigh as leg thickness.
            let samples = [Float(0.60), 0.70, 0.80].compactMap { fraction in
                contiguousThickness(
                    mask: mask,
                    center: hip + segment * fraction,
                    axis: perpendicular,
                    maximumDistance: maximum
                )
            }
            guard samples.count >= 2 else { return nil }
            return median(samples) / reference
        }

        guard let first = thighThickness(hip: chains[0].hip, knee: chains[0].knee),
              let second = thighThickness(hip: chains[1].hip, knee: chains[1].knee) else {
            throw AnalysisError.insufficientEvidence
        }
        let feature = PoseRegionFeature(
            pose: .legs,
            region: .thighs,
            normalizedValue: median([first, second]),
            source: .limbCrossSection,
            evidenceReason: nil
        )
        return SilhouetteProfile(
            scanId: extractedPose.scanId,
            pose: .legs,
            widthAtY: horizontalDebugProfile(mask),
            shoulderWidthRatio: 0,
            chestWidthRatio: 0,
            waistWidthRatio: 0,
            armMidWidthRatio: 0,
            thighMidWidthRatio: feature.normalizedValue,
            taperIndex: 0,
            chestToWaistRatio: 1,
            shoulderToWaistRatio: 1,
            hipWidthRatio: nil,
            lowerTorsoWidthRatio: 0,
            supportedRegions: [.thighs],
            regionFeatures: [feature],
            torsoReferencePixels: reference,
            poseMatchScore: extractedPose.poseMatchScore
        )
    }

    // MARK: - Coordinate system

    private static func coordinateSystem(mask: BinaryPersonMask, pose: ExtractedPose) throws -> PersonCoordinateSystem {
        func point(_ joint: String) -> AnalysisPoint? {
            let confidenceFloor = isSideView(pose.pose)
                ? minimumSideLandmarkConfidence
                : minimumLandmarkConfidence
            guard let landmark = pose.landmark(joint), landmark.confidence >= confidenceFloor,
                  landmark.x >= 0.02, landmark.x <= 0.98,
                  landmark.y >= 0.02, landmark.y <= 0.98 else { return nil }
            return AnalysisPoint(
                x: landmark.x * Float(mask.width - 1),
                y: landmark.y * Float(mask.height - 1)
            )
        }

        let shoulderCenter: AnalysisPoint
        let hipCenter: AnalysisPoint
        if isSideView(pose.pose) {
            let candidates = [
                ("leftShoulder", "leftHip", "leftElbow", "leftWrist"),
                ("rightShoulder", "rightHip", "rightElbow", "rightWrist")
            ].compactMap { shoulderName, hipName, elbowName, wristName -> (AnalysisPoint, AnalysisPoint, Float)? in
                guard let shoulder = point(shoulderName), let hip = point(hipName),
                      let shoulderLandmark = pose.landmark(shoulderName),
                      let hipLandmark = pose.landmark(hipName) else { return nil }
                let torsoConfidence = min(shoulderLandmark.confidence, hipLandmark.confidence)
                let hasCompleteArm = pose.landmark(elbowName).map { $0.confidence >= minimumSideLandmarkConfidence } == true
                    && pose.landmark(wristName).map { $0.confidence >= minimumSideLandmarkConfidence } == true
                return (shoulder, hip, torsoConfidence + (hasCompleteArm ? 1 : 0))
            }
            guard let strongest = candidates.max(by: { $0.2 < $1.2 }) else {
                throw AnalysisError.insufficientLandmarks
            }
            shoulderCenter = strongest.0
            hipCenter = strongest.1
        } else {
            guard let leftShoulder = point("leftShoulder"), let rightShoulder = point("rightShoulder"),
                  let leftHip = point("leftHip"), let rightHip = point("rightHip") else {
                throw AnalysisError.insufficientLandmarks
            }
            shoulderCenter = midpoint(leftShoulder, rightShoulder)
            hipCenter = midpoint(leftHip, rightHip)
        }

        let torsoVector = hipCenter - shoulderCenter
        let torsoLength = torsoVector.length
        guard torsoLength >= 12 else { throw AnalysisError.invalidReferenceScale }
        let down = torsoVector.normalized
        return PersonCoordinateSystem(
            shoulderCenter: shoulderCenter,
            hipCenter: hipCenter,
            downAxis: down,
            crossAxis: AnalysisPoint(x: -down.y, y: down.x),
            torsoLength: torsoLength
        )
    }

    // MARK: - Arm extraction

    private static func armFeature(
        mask: BinaryPersonMask,
        pose: ExtractedPose,
        coordinates: PersonCoordinateSystem
    ) -> PoseRegionFeature? {
        let left = armThickness(
            mask: mask,
            pose: pose,
            shoulder: "leftShoulder",
            elbow: "leftElbow",
            wrist: "leftWrist",
            torso: coordinates
        )
        let right = armThickness(
            mask: mask,
            pose: pose,
            shoulder: "rightShoulder",
            elbow: "rightElbow",
            wrist: "rightWrist",
            torso: coordinates
        )
        let values: [Float]
        if isSideView(pose.pose) {
            values = [left, right].compactMap { $0 }
            guard !values.isEmpty else { return nil }
        } else {
            guard let left, let right else { return nil }
            values = [left, right]
        }
        return PoseRegionFeature(
            pose: pose.pose,
            region: .arms,
            normalizedValue: median(values),
            source: .limbCrossSection,
            evidenceReason: nil
        )
    }

    private static func armThickness(
        mask: BinaryPersonMask,
        pose: ExtractedPose,
        shoulder: String,
        elbow: String,
        wrist: String,
        torso: PersonCoordinateSystem
    ) -> Float? {
        let confidenceFloor = isSideView(pose.pose)
            ? minimumSideLandmarkConfidence
            : minimumLandmarkConfidence
        guard let s = imagePoint(pose.landmark(shoulder), mask: mask, minimumConfidence: confidenceFloor),
              let e = imagePoint(pose.landmark(elbow), mask: mask, minimumConfidence: confidenceFloor),
              let w = imagePoint(pose.landmark(wrist), mask: mask, minimumConfidence: confidenceFloor),
              (w - e).length >= 8 else { return nil }
        let segment = e - s
        guard segment.length >= 8 else { return nil }
        let perpendicular = AnalysisPoint(x: -segment.normalized.y, y: segment.normalized.x)
        let maximum = max(3, Int((torso.torsoLength * 0.28).rounded()))
        let values = [Float(0.35), 0.50, 0.65].compactMap { fraction -> Float? in
            let center = s + segment * fraction
            guard let thickness = contiguousThickness(
                mask: mask,
                center: center,
                axis: perpendicular,
                maximumDistance: maximum
            ), thickness <= torso.torsoLength * 0.28 else { return nil }
            return thickness / torso.torsoLength
        }
        // The proximal 35% sample can legitimately touch the torso even with a
        // relaxed, separated arm. Reject that contaminated sample while still
        // requiring two independently supported cross-sections.
        guard values.count >= 2 else { return nil }
        return median(values)
    }

    // MARK: - Sampling

    static func contiguousThickness(
        mask: BinaryPersonMask,
        center: AnalysisPoint,
        axis: AnalysisPoint,
        maximumDistance: Int
    ) -> Float? {
        let direction = axis.normalized
        var adjusted = center
        if !foreground(mask, adjusted) {
            var replacement: AnalysisPoint?
            for distance in 1...3 {
                let d = Float(distance)
                let positive = center + direction * d
                let negative = center - direction * d
                if foreground(mask, positive) { replacement = positive; break }
                if foreground(mask, negative) { replacement = negative; break }
            }
            guard let replacement else { return nil }
            adjusted = replacement
        }

        func extent(sign: Float) -> (count: Int, hitLimit: Bool) {
            var count = 0
            for distance in 1...maximumDistance {
                let sample = adjusted + direction * (Float(distance) * sign)
                guard foreground(mask, sample) else { return (count, false) }
                count += 1
            }
            return (count, true)
        }

        let positive = extent(sign: 1)
        let negative = extent(sign: -1)
        guard !positive.hitLimit, !negative.hitLimit else { return nil }
        let thickness = positive.count + negative.count + 1
        return thickness >= 2 ? Float(thickness) : nil
    }

    private static func debugSamplingLines(
        mask: BinaryPersonMask,
        pose: ExtractedPose
    ) -> [SilhouetteSamplingLine] {
        guard let torso = try? coordinateSystem(mask: mask, pose: pose) else { return [] }
        let maximum = max(4, Int((torso.torsoLength * 0.9).rounded()))
        var lines: [SilhouetteSamplingLine] = []
        let torsoSamples: [(String, Float)] = [
            ("shoulders", 0.08), ("chest", 0.45), ("waist", 0.78)
        ]
        for (label, fraction) in torsoSamples {
            if let line = samplingLine(
                mask: mask,
                center: torso.point(down: fraction),
                axis: torso.crossAxis,
                maximumDistance: maximum,
                label: label
            ) { lines.append(line) }
        }

        for (side, shoulder, elbow) in [
            ("left_arm", "leftShoulder", "leftElbow"),
            ("right_arm", "rightShoulder", "rightElbow")
        ] {
            guard let start = imagePoint(pose.landmark(shoulder), mask: mask),
                  let end = imagePoint(pose.landmark(elbow), mask: mask) else { continue }
            let segment = end - start
            guard segment.length >= 8 else { continue }
            let perpendicular = AnalysisPoint(x: -segment.normalized.y, y: segment.normalized.x)
            for fraction in [Float(0.35), 0.50, 0.65] {
                if let line = samplingLine(
                    mask: mask,
                    center: start + segment * fraction,
                    axis: perpendicular,
                    maximumDistance: max(3, Int((torso.torsoLength * 0.28).rounded())),
                    label: "\(side)_\(Int(fraction * 100))"
                ) { lines.append(line) }
            }
        }
        return lines
    }

    private static func samplingLine(
        mask: BinaryPersonMask,
        center: AnalysisPoint,
        axis: AnalysisPoint,
        maximumDistance: Int,
        label: String
    ) -> SilhouetteSamplingLine? {
        let direction = axis.normalized
        guard foreground(mask, center) else { return nil }
        func edge(sign: Float) -> AnalysisPoint? {
            var last = center
            for distance in 1...maximumDistance {
                let candidate = center + direction * (Float(distance) * sign)
                guard foreground(mask, candidate) else { return last }
                last = candidate
            }
            return nil
        }
        guard let first = edge(sign: -1), let last = edge(sign: 1) else { return nil }
        return SilhouetteSamplingLine(
            label: label,
            startX: first.x,
            startY: first.y,
            endX: last.x,
            endY: last.y
        )
    }

    private static func foreground(_ mask: BinaryPersonMask, _ point: AnalysisPoint) -> Bool {
        mask.isForeground(x: Int(point.x.rounded()), y: Int(point.y.rounded()))
    }

    private static func imagePoint(
        _ landmark: NormalizedLandmark?,
        mask: BinaryPersonMask,
        minimumConfidence: Float = minimumLandmarkConfidence
    ) -> AnalysisPoint? {
        guard let landmark, landmark.confidence >= minimumConfidence,
              landmark.x >= 0.02, landmark.x <= 0.98,
              landmark.y >= 0.02, landmark.y <= 0.98 else { return nil }
        return AnalysisPoint(
            x: landmark.x * Float(mask.width - 1),
            y: landmark.y * Float(mask.height - 1)
        )
    }

    // MARK: - Vision

    static func personMask(cgImage: CGImage) async throws -> BinaryPersonMask {
        try await Task.detached(priority: .userInitiated) {
            let request = VNGeneratePersonSegmentationRequest()
            request.revision = personSegmentationRevision
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            try handler.perform([request])
            guard let buffer = request.results?.first?.pixelBuffer else { throw AnalysisError.noSegmentation }
            return copyMask(buffer)
        }.value
    }

    private static func copyMask(_ buffer: CVPixelBuffer) -> BinaryPersonMask {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return BinaryPersonMask(width: width, height: height, pixels: [])
        }
        let source = base.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { pixels[y * width + x] = source[y * bytesPerRow + x] }
        }
        return BinaryPersonMask(width: width, height: height, pixels: pixels)
    }

    private static func horizontalDebugProfile(_ mask: BinaryPersonMask, levels: Int = 100) -> [Float] {
        guard mask.width > 0, mask.height > 0, mask.pixels.count == mask.width * mask.height else { return [] }
        return (0..<levels).map { level in
            let y = min(mask.height - 1, Int(Float(level) / Float(levels) * Float(mask.height)))
            let xs = (0..<mask.width).filter { mask.isForeground(x: $0, y: y) }
            guard let first = xs.first, let last = xs.last else { return 0 }
            return Float(last - first + 1) / Float(mask.width)
        }
    }

    private static func midpoint(_ a: AnalysisPoint, _ b: AnalysisPoint) -> AnalysisPoint {
        AnalysisPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        if sorted.count.isMultiple(of: 2) {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return sorted[sorted.count / 2]
    }

    private static func isSideView(_ pose: Pose) -> Bool {
        pose == .side || pose == .sideChest
    }

    private static func supportsShoulderFeature(_ pose: Pose) -> Bool {
        switch pose {
        case .front, .back, .frontDoubleBicep, .backDoubleBicep, .mostMuscular:
            return true
        case .side, .sideChest, .relaxedAesthetic, .legs:
            return false
        }
    }

    private static func supportsChestFeature(_ pose: Pose) -> Bool {
        switch pose {
        case .front, .side, .frontDoubleBicep, .sideChest, .mostMuscular, .relaxedAesthetic:
            return true
        case .back, .backDoubleBicep, .legs:
            return false
        }
    }

    enum AnalysisError: Error {
        case noImage
        case noSegmentation
        case insufficientLandmarks
        case invalidReferenceScale
        case insufficientEvidence
    }
}
