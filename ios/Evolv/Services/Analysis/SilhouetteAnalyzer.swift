import UIKit
import Vision

/// Extracts silhouette width ratios from person segmentation masks.
/// Uses VNGeneratePersonSegmentationRequest (iOS 15+).
enum SilhouetteAnalyzer {

    static func analyze(image: UIImage, extractedPose: ExtractedPose) async throws -> SilhouetteProfile {
        guard let cgImage = image.cgImage else {
            throw AnalysisError.noImage
        }

        let maskBuffer = try await generateSegmentationMask(cgImage: cgImage)
        let widthAtY = extractWidthProfile(maskBuffer: maskBuffer, yLevels: 100)

        guard !widthAtY.isEmpty else {
            throw AnalysisError.emptyMask
        }

        let bodyH = extractedPose.bodyHeightPx
        let imageH = Float(cgImage.height)

        // Map anatomical Y positions using pose landmarks
        let headTopY  = extractedPose.landmark("nose").map { $0.y } ?? 0.05
        let shoulderY = midY(extractedPose.landmark("leftShoulder"), extractedPose.landmark("rightShoulder")) ?? 0.15
        let chestY    = midY(extractedPose.landmark("leftShoulder"), extractedPose.landmark("leftHip")).map { $0 * 0.4 + shoulderY * 0.6 } ?? 0.25
        let waistY    = midY(extractedPose.landmark("leftHip"), extractedPose.landmark("rightHip")).map { ($0 + shoulderY) / 2 } ?? 0.45
        let hipY      = midY(extractedPose.landmark("leftHip"), extractedPose.landmark("rightHip")) ?? 0.50
        let thighY    = midY(extractedPose.landmark("leftKnee"), extractedPose.landmark("leftHip")).map { ($0 + hipY) / 2 } ?? 0.65
        let armMidY   = midY(extractedPose.landmark("leftElbow"), extractedPose.landmark("leftShoulder")) ?? 0.30

        func widthAt(_ normalizedY: Float) -> Float {
            let idx = Int(normalizedY * Float(widthAtY.count - 1))
            return widthAtY[max(0, min(widthAtY.count - 1, idx))]
        }

        func avgWidth(around y: Float, window: Float = 0.03) -> Float {
            let lower = max(0, Int((y - window) * Float(widthAtY.count)))
            let upper = min(widthAtY.count, Int((y + window) * Float(widthAtY.count)))
            guard lower < upper else { return widthAt(y) }
            return widthAtY[lower..<upper].reduce(0, +) / Float(upper - lower)
        }

        let shoulderW = avgWidth(around: shoulderY)
        let chestW    = avgWidth(around: chestY)
        let waistW    = avgWidth(around: waistY)
        let hipW      = avgWidth(around: hipY)
        let thighW    = avgWidth(around: thighY)
        let armMidW   = avgWidth(around: armMidY, window: 0.02)

        // Taper = (shoulder - waist) / shoulder
        let taperIndex = shoulderW > 0 ? (shoulderW - waistW) / shoulderW : 0
        let chestToWaist = waistW > 0 ? chestW / waistW : 1
        let shoulderToWaist = waistW > 0 ? shoulderW / waistW : 1
        let lowerTorsoW = avgWidth(around: (waistY + hipY) / 2)

        // hipWidthRatio only meaningful for side/back poses
        let hipRatio: Float? = (extractedPose.pose == .side || extractedPose.pose == .back)
            ? hipW
            : nil

        return SilhouetteProfile(
            scanId: extractedPose.scanId,
            pose: extractedPose.pose,
            widthAtY: widthAtY,
            shoulderWidthRatio: shoulderW,
            chestWidthRatio: chestW,
            waistWidthRatio: waistW,
            armMidWidthRatio: armMidW,
            thighMidWidthRatio: thighW,
            taperIndex: taperIndex,
            chestToWaistRatio: chestToWaist,
            shoulderToWaistRatio: shoulderToWaist,
            hipWidthRatio: hipRatio,
            lowerTorsoWidthRatio: lowerTorsoW
        )
    }

    // MARK: - Segmentation

    private static func generateSegmentationMask(cgImage: CGImage) async throws -> CVPixelBuffer {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGeneratePersonSegmentationRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result = request.results?.first as? VNPixelBufferObservation else {
                    continuation.resume(throwing: AnalysisError.noSegmentation)
                    return
                }
                continuation.resume(returning: result.pixelBuffer)
            }
            request.qualityLevel = .balanced
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Width Profile

    /// Extracts normalized body width at each of `yLevels` vertical positions.
    /// Width is expressed as fraction of image width; divide by bodyHeightPx for normalization.
    private static func extractWidthProfile(maskBuffer: CVPixelBuffer, yLevels: Int) -> [Float] {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else { return [] }
        let width  = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        let pixels = baseAddress.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)

        var profile = [Float](repeating: 0, count: yLevels)

        for level in 0..<yLevels {
            let y = Int(Float(level) / Float(yLevels) * Float(height))
            let row = y * bytesPerRow

            var leftmost  = width
            var rightmost = -1
            var nonZeroCount = 0

            for x in 0..<width {
                let value = pixels[row + x]
                if value > 128 {
                    nonZeroCount += 1
                    if x < leftmost  { leftmost  = x }
                    if x > rightmost { rightmost = x }
                }
            }

            if rightmost >= leftmost && nonZeroCount > 2 {
                profile[level] = Float(rightmost - leftmost) / Float(width)
            }
        }

        return profile
    }

    // MARK: - Helpers

    private static func midY(_ a: NormalizedLandmark?, _ b: NormalizedLandmark?) -> Float? {
        guard let a, let b else { return nil }
        return (a.y + b.y) / 2
    }

    enum AnalysisError: Error {
        case noImage, noSegmentation, emptyMask
    }
}
