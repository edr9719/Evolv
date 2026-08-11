import XCTest
import UIKit
@testable import Evolv

final class CaptureReliabilityTests: XCTestCase {

    func testPrepareRendersRightOrientationIntoUprightPixels() {
        let base = solidImage(size: CGSize(width: 40, height: 20), color: .red)
        let rotated = UIImage(cgImage: base.cgImage!, scale: 1, orientation: .right)

        let prepared = PhotoStore.prepare(rotated)

        XCTAssertEqual(prepared.image.imageOrientation, .up)
        XCTAssertEqual(prepared.pixelSize.width, 20)
        XCTAssertEqual(prepared.pixelSize.height, 40)
        XCTAssertEqual(prepared.image.cgImage?.width, 20)
        XCTAssertEqual(prepared.image.cgImage?.height, 40)
    }

    func testPrepareCapsLongEdgeWithoutChangingAspectRatio() {
        let image = solidImage(size: CGSize(width: 4000, height: 2000), color: .blue)

        let prepared = PhotoStore.prepare(image, maxLongEdge: 1000)

        XCTAssertEqual(prepared.pixelSize, NormalizedPixelSize(width: 1000, height: 500))
    }

    func testZeroSecondAssessmentReturnsUnverifiedInsteadOfPassing() async {
        let image = solidImage(size: CGSize(width: 100, height: 200), color: .gray)

        let assessment = await QualityGateEngine.assessWithTimeout(
            image: image,
            expectedPose: .front,
            seconds: 0
        )

        XCTAssertEqual(assessment.status, .unavailable)
        XCTAssertTrue(assessment.confirmedIssues.isEmpty)
        XCTAssertFalse(assessment.hasSupportedUpperBodyEvidence)
    }

    func testDetectorUncertaintyDoesNotBecomeDistanceOrPoseWarning() async {
        let image = solidImage(size: CGSize(width: 100, height: 200), color: .gray)

        let front = await QualityGateEngine.assess(image: image, expectedPose: .front)
        let side = await QualityGateEngine.assess(image: image, expectedPose: .side)

        XCTAssertFalse(front.confirmedIssues.contains(.tooFarAway))
        XCTAssertFalse(side.confirmedIssues.contains(.tooFarAway))
        XCTAssertFalse(front.confirmedIssues.contains(.poseMismatch))
        XCTAssertFalse(side.confirmedIssues.contains(.poseMismatch))
    }

    func testAtomicSaveReportsWriteFailure() async throws {
        let image = solidImage(size: CGSize(width: 20, height: 20), color: .green)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await PhotoStore.save(image, filename: "capture.jpg", in: fileURL)
            XCTFail("Expected the write to fail")
        } catch let error as PhotoStore.StoreError {
            XCTAssertEqual(error.errorDescription, PhotoStore.StoreError.couldNotWrite.errorDescription)
        }
    }

    func testLegacyScanDecodesWithoutNewAssessmentFields() throws {
        let scanID = UUID()
        let captureID = UUID()
        let json = """
        {
          "id": "\(scanID.uuidString)",
          "date": 0,
          "captures": [{
            "id": "\(captureID.uuidString)",
            "pose": "front",
            "imageFilename": "legacy.jpg",
            "avgBrightness": 0.5,
            "aspectRatio": 0.75
          }],
          "consistencyScore": 80,
          "lightingScore": 85,
          "framingScore": 85
        }
        """

        let scan = try JSONDecoder().decode(Scan.self, from: Data(json.utf8))

        XCTAssertNil(scan.analysisAvailability)
        XCTAssertNil(scan.captures[0].assessment)
        XCTAssertNil(scan.captures[0].captureSource)
        XCTAssertNil(scan.captures[0].normalizedPixelSize)
        XCTAssertNil(scan.captures[0].cameraMetadata)
    }

    func testAssessmentOverrideRoundTripsWithCapture() throws {
        var assessment = QualityGateEngine.unavailableAssessment(reason: "test")
        assessment.status = .reviewRecommended
        assessment.confirmedIssues = [.tooDark]
        assessment.userOverrodeRecommendation = true
        let capture = PoseCapture(
            pose: .front,
            imageFilename: "photo.jpg",
            avgBrightness: 0.1,
            aspectRatio: 0.75,
            captureSource: .photoLibrary,
            assessment: assessment,
            normalizedPixelSize: NormalizedPixelSize(width: 1200, height: 1600),
            cameraMetadata: CaptureCameraMetadata(
                position: .front,
                lensType: "wide-angle",
                previewMirrored: true,
                outputMirrored: false,
                sourceOrientation: .right,
                normalizedOrientation: .up
            )
        )

        let decoded = try JSONDecoder().decode(
            PoseCapture.self,
            from: JSONEncoder().encode(capture)
        )

        XCTAssertEqual(decoded.assessment?.userOverrodeRecommendation, true)
        XCTAssertEqual(decoded.captureSource, .photoLibrary)
        XCTAssertEqual(decoded.cameraMetadata, capture.cameraMetadata)
    }

    func testCameraPreferenceDefaultsToFrontAndPersistsSelection() throws {
        let suiteName = "CameraPreferenceStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(CameraPreferenceStore.load(from: defaults), .front)

        CameraPreferenceStore.save(.rear, to: defaults)
        XCTAssertEqual(CameraPreferenceStore.load(from: defaults), .rear)
    }

    func testKnownCameraConfigurationsRequireMatchingPositionAndLens() {
        let frontWide = cameraMetadata(position: .front, lensType: "wide")
        let frontWideAgain = cameraMetadata(position: .front, lensType: "wide")
        let rearWide = cameraMetadata(position: .rear, lensType: "wide")
        let frontDifferentLens = cameraMetadata(position: .front, lensType: "true-depth")

        XCTAssertTrue(frontWide.isComparable(with: frontWideAgain))
        XCTAssertFalse(frontWide.isComparable(with: rearWide))
        XCTAssertFalse(frontWide.isComparable(with: frontDifferentLens))
    }

    func testAllThreeStandardPosesAreRequired() {
        let front = capture(.front)
        let side = capture(.side)
        let back = capture(.back)
        let optional = capture(.legs)

        XCTAssertFalse(ScanCaptureValidator.hasAllRequiredPoses([front, side, optional]))
        XCTAssertTrue(ScanCaptureValidator.hasAllRequiredPoses([front, side, back]))
    }

    func testMissingArmEvidenceKeepsScanFromBeingCalledComparable() {
        var ready = CaptureAssessment(
            status: .ready,
            confirmedIssues: [],
            regionEvidence: Dictionary(uniqueKeysWithValues: CaptureRegion.allCases.map { ($0, .supported) }),
            userOverrodeRecommendation: false,
            brightnessScore: 0.5,
            coverageScore: 1
        )
        var assessments: [Pose: CaptureAssessment] = [.front: ready, .side: ready, .back: ready]
        XCTAssertTrue(ScanCaptureValidator.hasComparableUpperBodyEvidence(assessments))
        ready.regionEvidence[.arms] = .unavailable("arms_not_verified")
        assessments[.front] = ready

        XCTAssertFalse(ScanCaptureValidator.hasComparableUpperBodyEvidence(assessments))
    }

    private func capture(_ pose: Pose) -> PoseCapture {
        PoseCapture(pose: pose, imageFilename: "\(pose.rawValue).jpg", avgBrightness: 0.5, aspectRatio: 0.75)
    }

    private func cameraMetadata(
        position: CaptureCameraPosition,
        lensType: String
    ) -> CaptureCameraMetadata {
        CaptureCameraMetadata(
            position: position,
            lensType: lensType,
            previewMirrored: position == .front,
            outputMirrored: false,
            sourceOrientation: .up,
            normalizedOrientation: .up
        )
    }

    private func solidImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
