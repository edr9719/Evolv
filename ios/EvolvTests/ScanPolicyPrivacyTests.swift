import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Evolv

final class ScanPolicyPrivacyTests: XCTestCase {

    func testDefaultTestPlanDisablesNetworking() {
        XCTAssertEqual(ProcessInfo.processInfo.environment["EVOLV_ALLOW_NETWORK"], "0")
    }

    func testSecondCanonicalScanOnSameDayBecomesDocumentationOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = Date(timeIntervalSince1970: 1_786_089_600)
        let evening = morning.addingTimeInterval(8 * 3_600)
        let existing = scan(date: morning, role: .canonical)

        XCTAssertEqual(
            ScanSchedulingPolicy.resolvedRole(
                requested: .canonical,
                on: evening,
                existingScans: [existing],
                calendar: calendar
            ),
            .sameDayExtra
        )
    }

    func testExtraDoesNotBlockFirstCanonicalScanForTheDay() {
        let date = Date(timeIntervalSince1970: 1_786_089_600)
        let existing = scan(date: date, role: .sameDayExtra)

        XCTAssertEqual(
            ScanSchedulingPolicy.resolvedRole(
                requested: .canonical,
                on: date,
                existingScans: [existing]
            ),
            .canonical
        )
    }

    func testDocumentationOnlyIntentNeverBecomesCanonical() {
        let date = Date(timeIntervalSince1970: 1_786_089_600)
        XCTAssertEqual(
            ScanSchedulingPolicy.resolvedRole(
                requested: .documentationOnly,
                on: date,
                existingScans: []
            ),
            .documentationOnly
        )
    }

    func testThreeSavedRequiredPhotosAreCompleteDespiteUnavailableAutomaticChecks() {
        let captures = Pose.required.map { pose in
            PoseCapture(
                pose: pose,
                imageFilename: "\(pose.rawValue).jpg",
                avgBrightness: 0.5,
                aspectRatio: 0.75,
                captureSource: .camera,
                assessment: .legacyUnverified(),
                normalizedPixelSize: NormalizedPixelSize(width: 1_200, height: 1_600)
            )
        }

        XCTAssertTrue(ScanCaptureValidator.hasAllRequiredPoses(captures))
        XCTAssertFalse(ScanCaptureValidator.hasComparableUpperBodyEvidence(captures))
    }

    func testLibraryPhotoStaysInTimelineButCannotEnterAutomaticScaleComparison() {
        let library = PoseCapture(
            pose: .front,
            imageFilename: "library.jpg",
            avgBrightness: 0.5,
            aspectRatio: 0.75,
            captureSource: .photoLibrary
        )
        let cameraWithoutMetadata = PoseCapture(
            pose: .front,
            imageFilename: "camera.jpg",
            avgBrightness: 0.5,
            aspectRatio: 0.75,
            captureSource: .camera
        )
        var legacy = library
        legacy.captureSource = nil
        var explicitlyLegacy = library
        explicitlyLegacy.captureSource = .legacy
        var camera = cameraWithoutMetadata
        camera.cameraMetadata = CaptureCameraMetadata(
            position: .front,
            lensType: "wide",
            previewMirrored: true,
            outputMirrored: false,
            sourceOrientation: .up,
            normalizedOrientation: .up,
            zoomFactor: 1
        )

        XCTAssertFalse(AnalysisCapturePolicy.isEligibleForAutomaticComparison(library))
        XCTAssertFalse(AnalysisCapturePolicy.isEligibleForAutomaticComparison(cameraWithoutMetadata))
        XCTAssertTrue(AnalysisCapturePolicy.isEligibleForAutomaticComparison(camera))
        XCTAssertTrue(AnalysisCapturePolicy.isEligibleForAutomaticComparison(legacy))
        XCTAssertTrue(AnalysisCapturePolicy.isEligibleForAutomaticComparison(explicitlyLegacy))
    }

    func testTargetedRepairPreservesEveryUnselectedCapture() {
        let front = capture(.front, filename: "front-old.jpg")
        let side = capture(.side, filename: "side-old.jpg")
        let back = capture(.back, filename: "back-old.jpg")
        let showcase = capture(.frontDoubleBicep, filename: "showcase.jpg")
        let replacement = capture(.side, filename: "side-new.jpg")

        let result = ScanCaptureMerge.replacing(
            [front, side, back, showcase],
            with: [replacement]
        )

        XCTAssertEqual(result.supersededFilenames, ["side-old.jpg"])
        XCTAssertEqual(result.captures.first(where: { $0.pose == .front })?.id, front.id)
        XCTAssertEqual(result.captures.first(where: { $0.pose == .back })?.id, back.id)
        XCTAssertEqual(result.captures.first(where: { $0.pose == .frontDoubleBicep })?.id, showcase.id)
        XCTAssertEqual(result.captures.first(where: { $0.pose == .side })?.id, replacement.id)
    }

    func testEveryNonLegPoseUsesUpperBodyReferenceFraming() {
        for pose in Pose.allCases where pose != .legs {
            guard case .torsoUp = pose.framing else {
                return XCTFail("\(pose.rawValue) should use upper-body framing")
            }
        }
        guard case .legsOnly = Pose.legs.framing else {
            return XCTFail("The legs pose should use lower-body framing")
        }
    }

    func testEveryPoseHasUniqueReferenceAssetAndManualChecklist() {
        let assetNames = Pose.allCases.map(\.referenceAssetName)

        XCTAssertEqual(Set(assetNames).count, Pose.allCases.count)
        for pose in Pose.allCases {
            XCTAssertEqual(pose.reviewChecklist(matchingPrevious: false).count, 4)
            XCTAssertEqual(pose.reviewChecklist(matchingPrevious: true).count, 4)
            XCTAssertTrue(
                pose.reviewChecklist(matchingPrevious: true).last?.contains("previous") == true,
                "\(pose.rawValue) should explain that repeat scans match the local previous photo"
            )
        }
    }

    func testCloudInsightsDefaultOffWhenPreferenceIsAbsent() throws {
        let encoded = try JSONEncoder().encode(UserProfile())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "cloudInsightsEnabled")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(UserProfile.self, from: legacyData)

        XCTAssertFalse(decoded.usesCloudInsights)
        XCTAssertNil(decoded.captureRecipe)
        XCTAssertFalse(decoded.usesLocalOnlyStorage)
    }

    func testAppleBackupIsDefaultAndLocalOnlyPreferenceIsExplicit() throws {
        let suiteName = "DeviceBackupPolicyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("evolv-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertFalse(DeviceBackupPolicy.isLocalOnly(defaults: defaults))
        try DeviceBackupPolicy.setLocalOnly(true, defaults: defaults, documentsURL: directory)
        XCTAssertTrue(DeviceBackupPolicy.isLocalOnly(defaults: defaults))
        XCTAssertEqual(DeviceBackupPolicy.isExcludedFromBackup(at: directory), true)

        try DeviceBackupPolicy.setLocalOnly(false, defaults: defaults, documentsURL: directory)
        XCTAssertFalse(DeviceBackupPolicy.isLocalOnly(defaults: defaults))
        XCTAssertEqual(DeviceBackupPolicy.isExcludedFromBackup(at: directory), false)
    }

    func testCloudDisabledDoesNotContactInsightService() async {
        let spy = InsightSpy()

        let insight = await InsightEngine.generateInsight(
            signals: comparableSignals(),
            networkProxy: spy,
            allowCloud: false
        )
        let requestCount = await spy.requestCount

        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(insight.source, .templateFallback)
    }

    func testCloudPayloadContainsOnlyDerivedSignals() throws {
        let data = try NetworkProxy.encodedRequestBody(signals: comparableSignals())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = allKeys(in: object)

        XCTAssertEqual(Set(object.keys), Set(["signals"]))
        XCTAssertFalse(keys.contains("userId"))
        XCTAssertFalse(keys.contains("image"))
        XCTAssertFalse(keys.contains("imageFilename"))
        XCTAssertFalse(keys.contains("landmarks"))
        XCTAssertFalse(keys.contains("rawMeasurements"))
    }

    func testPreparedJPEGStripsLocationMetadata() throws {
        let original = try jpegWithGPSMetadata()
        XCTAssertTrue(hasGPSMetadata(original))
        let image = try XCTUnwrap(UIImage(data: original))

        let prepared = PhotoStore.prepare(image)
        let encoded = try XCTUnwrap(prepared.image.jpegData(compressionQuality: 0.9))

        XCTAssertFalse(hasGPSMetadata(encoded))
    }

    func testSavedPhotoUsesCompleteFileProtection() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30))
        let image = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        let filename = "protection-\(UUID().uuidString).jpg"
        defer { PhotoStore.delete(named: filename) }

        _ = try await PhotoStore.save(image, filename: filename)

        XCTAssertTrue(PhotoStore.protectedWriteOptions.contains(.completeFileProtection))
        #if targetEnvironment(simulator)
        // The simulator host filesystem does not expose NSFileProtectionKey.
        XCTAssertNotNil(PhotoStore.loadImage(named: filename))
        #else
        XCTAssertEqual(PhotoStore.fileProtection(for: filename), .complete)
        #endif
    }

    private func scan(date: Date, role: ScanRole) -> Scan {
        Scan(
            date: date,
            captures: [],
            consistencyScore: 0,
            lightingScore: 0,
            framingScore: 0,
            note: nil,
            context: nil,
            analysisAvailability: role == .canonical ? .baselineOnly : .documentationOnly,
            captureCompleteness: .incomplete,
            scanRole: role,
            lastModifiedAt: date
        )
    }

    private func capture(_ pose: Pose, filename: String) -> PoseCapture {
        PoseCapture(
            pose: pose,
            imageFilename: filename,
            avgBrightness: 0.5,
            aspectRatio: 0.75
        )
    }

    private func comparableSignals() -> InterpretedSignals {
        InterpretedSignals(
            scanCount: 3,
            weeksTracked: 2,
            reliabilityTier: .earlyStage,
            goal: .recomp,
            overallConfidence: .low,
            signals: [BodyRegion.waist.rawValue: .minimalNegative],
            taperSignal: .unclear,
            proportionSignal: .unclear,
            measurementAlignment: [:],
            recompositionPatterns: [],
            scanQualityNotes: [],
            signalConflicts: [],
            contextNotes: [],
            unavailableRegions: [BodyRegion.arms.rawValue: "insufficient_supported_comparison_evidence"],
            analysisAvailability: .comparable
        )
    }

    private func allKeys(in value: Any) -> Set<String> {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: Set(dictionary.keys)) { result, entry in
                result.formUnion(allKeys(in: entry.value))
            }
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { result, item in
                result.formUnion(allKeys(in: item))
            }
        }
        return []
    }

    private func jpegWithGPSMetadata() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 10.75,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 106.67,
            kCGImagePropertyGPSLongitudeRef: "E"
        ]
        let properties: [CFString: Any] = [kCGImagePropertyGPSDictionary: gps]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func hasGPSMetadata(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary? else {
            return false
        }
        return properties.object(forKey: kCGImagePropertyGPSDictionary) != nil
    }
}

private actor InsightSpy: InsightRequesting {
    private(set) var requestCount = 0

    func requestInsight(signals: InterpretedSignals) async -> GeneratedInsight? {
        requestCount += 1
        return nil
    }
}
