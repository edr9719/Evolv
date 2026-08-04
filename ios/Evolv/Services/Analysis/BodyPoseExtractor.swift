import UIKit
import Vision

/// Extracts and normalizes body pose landmarks from an image using VNDetectHumanBodyPoseRequest.
/// Coordinates are in normalized image space (0–1), with Y flipped to match UIKit (top-left origin).
enum BodyPoseExtractor {

    // Joint mapping: Vision joint → simplified string key stored in NormalizedLandmark
    private static let jointMapping: [(VNHumanBodyPoseObservation.JointName, String)] = [
        (.nose,          "nose"),
        (.leftShoulder,  "leftShoulder"),
        (.rightShoulder, "rightShoulder"),
        (.leftElbow,     "leftElbow"),
        (.rightElbow,    "rightElbow"),
        (.leftWrist,     "leftWrist"),
        (.rightWrist,    "rightWrist"),
        (.leftHip,       "leftHip"),
        (.rightHip,      "rightHip"),
        (.leftKnee,      "leftKnee"),
        (.rightKnee,     "rightKnee"),
        (.leftAnkle,     "leftAnkle"),
        (.rightAnkle,    "rightAnkle"),
        (.root,          "root")
    ]

    // MARK: - Public API

    static func extract(from image: UIImage, pose: Pose, scanId: UUID) async throws -> ExtractedPose {
        guard let cgImage = image.cgImage else {
            throw ExtractionError.noImage
        }

        let observation = try await detectPose(cgImage: cgImage)
        var landmarks: [NormalizedLandmark] = []

        for (joint, key) in jointMapping {
            guard let point = try? observation.recognizedPoint(joint), point.confidence > 0.1 else {
                continue
            }
            landmarks.append(NormalizedLandmark(
                joint: key,
                x: Float(point.location.x),
                y: Float(1.0 - point.location.y), // flip Y: Vision uses bottom-left origin
                confidence: Float(point.confidence)
            ))
        }

        if landmarks.count < 4 {
            throw ExtractionError.insufficientLandmarks
        }

        let bodyHeightPx = computeBodyHeight(landmarks: landmarks, imageHeight: Float(cgImage.height))

        return ExtractedPose(
            scanId: scanId,
            pose: pose,
            landmarks: landmarks,
            bodyHeightPx: bodyHeightPx,
            poseMatchScore: nil // filled by NormalizationEngine later
        )
    }

    // MARK: - Pose Match Score

    /// Computes a pose-match score (0–1) between two ExtractedPose sets.
    /// Higher = more similar pose angles, better for delta comparison.
    static func computePoseMatchScore(a: ExtractedPose, b: ExtractedPose) -> Float {
        let referenceHeight: Float = 400

        let keyJoints = [
            ("leftShoulder", "rightShoulder"),
            ("leftHip", "rightHip"),
            ("leftElbow", "leftWrist"),
            ("rightElbow", "rightWrist"),
            ("leftShoulder", "leftHip"),
            ("rightShoulder", "rightHip"),
            ("leftHip", "leftKnee"),
            ("rightHip", "rightKnee"),
            ("nose", "root")
        ]

        var totalDiff: Float = 0
        var count: Int = 0

        for (j1, j2) in keyJoints {
            guard let a1 = a.landmark(j1), let a2 = a.landmark(j2),
                  let b1 = b.landmark(j1), let b2 = b.landmark(j2) else { continue }

            let aDist = distance(a1, a2) * a.bodyHeightPx
            let bDist = distance(b1, b2) * b.bodyHeightPx

            // Normalize to reference height
            let aNorm = aDist / max(a.bodyHeightPx, 1) * referenceHeight
            let bNorm = bDist / max(b.bodyHeightPx, 1) * referenceHeight

            totalDiff += abs(aNorm - bNorm)
            count += 1
        }

        guard count > 0 else { return 0.5 }
        let avgDiff = totalDiff / Float(count)
        // Normalize: diff of 20px → 0.5, diff of 0 → 1.0
        return max(0, 1.0 - avgDiff / 40.0)
    }

    // MARK: - Private

    private static func detectPose(cgImage: CGImage) async throws -> VNHumanBodyPoseObservation {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectHumanBodyPoseRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let obs = request.results?.first as? VNHumanBodyPoseObservation else {
                    continuation.resume(throwing: ExtractionError.noObservation)
                    return
                }
                continuation.resume(returning: obs)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func computeBodyHeight(landmarks: [NormalizedLandmark], imageHeight: Float) -> Float {
        // Try nose → ankle midpoint for full-body height in pixels
        if let nose = landmarks.first(where: { $0.joint == "nose" }),
           let lAnkle = landmarks.first(where: { $0.joint == "leftAnkle" }),
           let rAnkle = landmarks.first(where: { $0.joint == "rightAnkle" }) {
            let ankleY = (lAnkle.y + rAnkle.y) / 2
            return abs(ankleY - nose.y) * imageHeight
        }
        // Fallback: use hip-to-nose * 1/0.55 ≈ full body
        if let nose = landmarks.first(where: { $0.joint == "nose" }),
           let lHip = landmarks.first(where: { $0.joint == "leftHip" }),
           let rHip = landmarks.first(where: { $0.joint == "rightHip" }) {
            let hipY = (lHip.y + rHip.y) / 2
            return abs(hipY - nose.y) * imageHeight / 0.55
        }
        // Last resort: shoulder span / 0.22 ≈ body height
        if let ls = landmarks.first(where: { $0.joint == "leftShoulder" }),
           let rs = landmarks.first(where: { $0.joint == "rightShoulder" }) {
            let span = abs(ls.x - rs.x) * imageHeight
            return span / 0.22
        }
        return imageHeight * 0.8 // rough fallback
    }

    private static func distance(_ a: NormalizedLandmark, _ b: NormalizedLandmark) -> Float {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    enum ExtractionError: Error {
        case noImage, noObservation, insufficientLandmarks
    }
}

// MARK: - Helpers

extension ExtractedPose {
    func landmark(_ joint: String) -> NormalizedLandmark? {
        landmarks.first { $0.joint == joint }
    }
}

extension Array where Element == NormalizedLandmark {
    func landmark(_ joint: String) -> NormalizedLandmark? {
        first { $0.joint == joint }
    }
}
