import XCTest
import UIKit
import CoreImage
import ImageIO
@testable import Evolv

final class AnalysisFixtureDeviceTests: XCTestCase {
    private struct Manifest: Decodable {
        struct Fixture: Decodable {
            var id: String
            var asset: String
            var pose: Pose
            var expectedCondition: String
        }
        var schemaVersion: Int
        var consentClassification: String
        var fixtures: [Fixture]
        var expectedAnalyticalRegions: [BodyRegion]
        var deterministicTransformations: [String]
        var deliberatelyInvalid: [String]
    }

    private struct ProcessedPose {
        var fixture: Manifest.Fixture
        var image: UIImage
        var extracted: ExtractedPose
        var profile: SilhouetteProfile
        var debug: SilhouetteDebugArtifact
        var processingDurationSeconds: Double
    }

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["EVOLV_VISION_DEVICE_TESTS"] == "1" else {
            throw XCTSkip("Physical-device Vision fixtures are disabled in the unit test plan.")
        }
        #if targetEnvironment(simulator)
        XCTFail("Evolv-Vision-Device.xctestplan must run on an explicit physical iPhone destination.")
        #endif
        XCTAssertEqual(ProcessInfo.processInfo.environment["EVOLV_ALLOW_NETWORK"], "0")
    }

    func testPublicManifestAndFourIdenticalWeeksRemainStable() async throws {
        let started = ProcessInfo.processInfo.systemUptime
        let manifest = try loadManifest()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.consentClassification, "public_generated")
        XCTAssertEqual(manifest.fixtures.count, 9)
        let required = manifest.fixtures.filter { $0.expectedCondition == "valid_mandatory" }
        let expectedRegions = Set(manifest.expectedAnalyticalRegions)
        XCTAssertEqual(Set(required.map(\.pose)), Set(Pose.required))

        let baselineProcessed = try await process(required)
        var history = [analysis(profiles: baselineProcessed.map(\.profile), week: 0)]
        for week in 1...3 {
            let processed = try await process(required, baseline: baselineProcessed)
            let signals = VisualSignalEngine.compute(
                currentProfiles: processed.map(\.profile),
                allScanAnalyses: history,
                thresholds: .engineeringV1
            )
            XCTAssertEqual(Set(signals.deltas.map(\.region)), expectedRegions)
            XCTAssertTrue(signals.regionalComparisons?
                .filter { expectedRegions.contains($0.region) }
                .allSatisfy { $0.status == .stable } == true)
            XCTAssertEqual(
                signals.regionalComparisons?.first(where: { $0.region == .arms })?.status,
                .unavailable,
                "The generated references intentionally expose no isolated arm cross-section."
            )
            XCTAssertTrue(signals.deltas.allSatisfy { $0.normalizedDelta == 0 })
            history.append(analysis(profiles: processed.map(\.profile), week: week, signals: signals))
        }

        for processed in baselineProcessed {
            attachDebug(processed, name: processed.fixture.id)
        }
        attachReport(
            fixture: "identical-four-weeks",
            availability: .comparable,
            signals: history.last?.visualSignals ?? VisualSignalSet(deltas: [], fatLossSignals: nil, reliabilityTier: .baseline),
            duration: ProcessInfo.processInfo.systemUptime - started,
            failures: [:],
            processed: baselineProcessed
        )
    }

    func testAllValidImageTransformationsRemainStableAndSupported() async throws {
        let manifest = try loadManifest()
        let required = manifest.fixtures.filter { $0.expectedCondition == "valid_mandatory" }
        let expectedRegions = Set(manifest.expectedAnalyticalRegions)
        let baseline = try await process(required)
        let baselineAnalysis = analysis(profiles: baseline.map(\.profile), week: 0)
        var rows = ["transformation,region,status,delta,pose,contribution_status,pose_delta,pose_match,reason"]
        var failures: [String: String] = [:]

        for name in manifest.deterministicTransformations {
            do {
                let transformed = try required.map { fixture -> (Manifest.Fixture, UIImage) in
                    (fixture, try transform(try image(for: fixture), named: name))
                }
                let current = try await process(transformed, baseline: baseline)
                let result = VisualSignalEngine.compute(
                    currentProfiles: current.map(\.profile),
                    allScanAnalyses: [baselineAnalysis],
                    thresholds: .engineeringV1
                )
                for comparison in result.regionalComparisons ?? [] {
                    for contribution in comparison.contributions {
                        rows.append([
                            name,
                            comparison.region.rawValue,
                            comparison.status.rawValue,
                            String(comparison.normalizedDelta ?? .nan),
                            contribution.pose.rawValue,
                            contribution.status.rawValue,
                            String(contribution.normalizedDelta ?? .nan),
                            String(contribution.poseMatchScore ?? .nan),
                            contribution.reason ?? comparison.reason ?? ""
                        ].joined(separator: ","))
                    }
                    if expectedRegions.contains(comparison.region) {
                        XCTAssertEqual(comparison.status, .stable, "\(name) made \(comparison.region.rawValue) non-stable")
                    } else {
                        XCTAssertEqual(comparison.status, .unavailable, "\(name) fabricated unsupported \(comparison.region.rawValue) evidence")
                    }
                }
                XCTAssertEqual(Set(result.deltas.map(\.region)), expectedRegions, "\(name) changed expected analytical coverage")
            } catch {
                failures[name] = String(describing: error)
                XCTFail("Valid transformation \(name) became unavailable: \(error)")
            }
        }
        add(XCTAttachment(
            data: Data(rows.joined(separator: "\n").utf8),
            uniformTypeIdentifier: "public.comma-separated-values-text"
        ))
        XCTAssertTrue(failures.isEmpty)
    }

    func testDeliberatelyInvalidFixturesAreUnavailableNotStable() async throws {
        let manifest = try loadManifest()
        let required = manifest.fixtures.filter { $0.expectedCondition == "valid_mandatory" }
        let baseline = try await process(required)
        let baselineAnalysis = analysis(profiles: baseline.map(\.profile), week: 0)

        for invalid in manifest.deliberatelyInvalid {
            var profiles: [SilhouetteProfile] = []
            let wrongPoseImage = try manifest.fixtures
                .first(where: { $0.pose == .frontDoubleBicep })
                .map { try image(for: $0) }
            for fixture in required {
                let source = invalid == "pose" ? try XCTUnwrap(wrongPoseImage) : try image(for: fixture)
                let image = try invalidTransform(source, named: invalid)
                if let processed = try? await process([(fixture, image)], baseline: baseline) {
                    profiles.append(contentsOf: processed.map(\.profile))
                }
            }
            let result = VisualSignalEngine.compute(
                currentProfiles: profiles,
                allScanAnalyses: [baselineAnalysis],
                thresholds: .engineeringV1
            )
            XCTAssertTrue(
                result.regionalComparisons?.allSatisfy { $0.status == .unavailable } == true,
                "Invalid \(invalid) fixture must abstain instead of becoming stable"
            )
            XCTAssertTrue(result.deltas.isEmpty)
        }
    }

    func testThreePosePerformanceAndRegressionBaseline() throws {
        let manifest = try loadManifest()
        let required = manifest.fixtures.filter { $0.expectedCondition == "valid_mandatory" }
        var durations: [Double] = []

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTStorageMetric()]) {
            let started = ProcessInfo.processInfo.systemUptime
            let expectation = expectation(description: "three-pose Vision analysis")
            Task {
                _ = try? await self.process(required)
                durations.append(ProcessInfo.processInfo.systemUptime - started)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 90)
        }

        let median = durations.sorted()[durations.count / 2]
        let key = [
            UIDevice.current.model,
            UIDevice.current.systemVersion,
            "analysis-4",
            "pose-\(BodyPoseExtractor.bodyPoseRevision)",
            "segmentation-\(SilhouetteAnalyzer.personSegmentationRevision)",
            SilhouetteAnalyzer.segmentationQualityIdentifier
        ].joined(separator: "|")
        let store = UserDefaults.standard
        let baselineKey = "evolv.fixture.performance.\(key)"
        if let previous = store.object(forKey: baselineKey) as? Double {
            XCTAssertLessThanOrEqual(median, previous * 1.20, "Median three-pose time regressed more than 20%")
            store.set(min(previous, median), forKey: baselineKey)
        } else {
            store.set(median, forKey: baselineKey)
        }
        add(XCTAttachment(
            data: Data("device_os,median_seconds\n\(key),\(median)".utf8),
            uniformTypeIdentifier: "public.comma-separated-values-text"
        ))
    }

    func testFiveSetConsistencyProtocolWithIdenticalPublicFixtures() async throws {
        let manifest = try loadManifest()
        let required = manifest.fixtures.filter { $0.expectedCondition == "valid_mandatory" }
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_786_089_600)
        let camera = CaptureCameraMetadata(
            position: .rear,
            lensType: "public-fixture-wide",
            previewMirrored: false,
            outputMirrored: false,
            sourceOrientation: .up,
            normalizedOrientation: .up
        )
        var images: [String: UIImage] = [:]
        var scans: [Scan] = []
        var records: [ValidationSetRecord] = []

        for setNumber in 1...ValidationStudySession.requiredSetCount {
            let scanID = UUID()
            let captures = try required.map { fixture -> PoseCapture in
                let filename = "fixture-set-\(setNumber)-\(fixture.pose.rawValue).jpg"
                images[filename] = try image(for: fixture)
                return PoseCapture(
                    pose: fixture.pose,
                    imageFilename: filename,
                    avgBrightness: 0.5,
                    aspectRatio: 0.75,
                    captureSource: .camera,
                    assessment: .legacyUnverified(),
                    normalizedPixelSize: NormalizedPixelSize(width: 1_200, height: 1_600),
                    cameraMetadata: camera
                )
            }
            let date = startedAt.addingTimeInterval(Double(setNumber - 1) * 60)
            scans.append(Scan(
                id: scanID,
                date: date,
                captures: captures,
                consistencyScore: 0,
                lightingScore: 0,
                framingScore: 0,
                note: nil,
                context: nil,
                analysisAvailability: setNumber == 1 ? .baselineOnly : .validationOnly,
                captureCompleteness: .complete,
                scanRole: setNumber == 1 ? .canonical : .validationRepeat,
                lastModifiedAt: date,
                validationSessionID: sessionID,
                validationSetNumber: setNumber
            ))
            records.append(ValidationSetRecord(
                setNumber: setNumber,
                scanID: scanID,
                completedAt: date,
                conditions: ValidationSetConditions(
                    stayedTheSame: true,
                    deviations: [],
                    recordedAt: date
                ),
                comparison: nil,
                usedExistingCanonicalScan: false
            ))
        }

        let session = ValidationStudySession(
            id: sessionID,
            enrollment: ValidationEnrollment(
                enrolledAt: startedAt,
                programVersion: ValidationStudySession.protocolVersion,
                shareScope: .localOnly,
                consentVersion: nil
            ),
            startedAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(ValidationStudySession.maximumDuration),
            status: .evaluating,
            lockedCameraPosition: .rear,
            lockedLensType: camera.lensType,
            sets: records,
            draftSetNumber: nil,
            draftCaptures: [],
            result: nil,
            statusReasons: [],
            completedAt: nil
        )

        let evaluation = await ValidationConsistencyEngine.evaluate(
            session: session,
            scans: scans,
            loadPhoto: { images[$0] },
            now: startedAt.addingTimeInterval(10 * 60)
        )

        XCTAssertEqual(evaluation.status, .consistent)
        XCTAssertEqual(Set(evaluation.comparisonsBySet.keys), Set(2...5))
        for comparison in evaluation.comparisonsBySet.values {
            XCTAssertTrue(comparison.failures.isEmpty)
            XCTAssertTrue(comparison.hasSufficientCoreEvidence)
            XCTAssertTrue(comparison.regionalComparisons
                .filter { [.shoulders, .chest, .waist].contains($0.region) }
                .allSatisfy { $0.status == .stable && $0.normalizedDelta == 0 })
        }
    }

    // MARK: - Processing

    private func process(
        _ fixtures: [Manifest.Fixture],
        baseline: [ProcessedPose]? = nil
    ) async throws -> [ProcessedPose] {
        try await process(try fixtures.map { ($0, try image(for: $0)) }, baseline: baseline)
    }

    private func process(
        _ fixtures: [(Manifest.Fixture, UIImage)],
        baseline: [ProcessedPose]? = nil
    ) async throws -> [ProcessedPose] {
        var output: [ProcessedPose] = []
        for (fixture, input) in fixtures {
            let started = ProcessInfo.processInfo.systemUptime
            let image = PhotoStore.prepare(input).image
            var extracted = try await BodyPoseExtractor.extract(from: image, pose: fixture.pose, scanId: UUID())
            if let prior = baseline?.first(where: { $0.fixture.pose == fixture.pose }) {
                extracted.poseMatchScore = NormalizationEngine.computePoseMatchScore(a: extracted, b: prior.extracted)
            }
            let analyzed: (profile: SilhouetteProfile, debug: SilhouetteDebugArtifact)
            do {
                analyzed = try await SilhouetteAnalyzer.analyzeWithDebug(image: image, extractedPose: extracted)
            } catch {
                let landmarkSummary = extracted.landmarks
                    .sorted { $0.joint < $1.joint }
                    .map { "\($0.joint)=\(String(format: "%.3f", $0.confidence))" }
                    .joined(separator: ",")
                throw FixtureError.processing(
                    fixture: fixture.id,
                    pose: fixture.pose.rawValue,
                    reason: String(describing: error),
                    landmarks: landmarkSummary
                )
            }
            output.append(ProcessedPose(
                fixture: fixture,
                image: image,
                extracted: extracted,
                profile: analyzed.profile,
                debug: analyzed.debug,
                processingDurationSeconds: ProcessInfo.processInfo.systemUptime - started
            ))
        }
        return output
    }

    private func loadManifest() throws -> Manifest {
        let bundle = Bundle(for: AnalysisFixtureDeviceTests.self)
        let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "Fixtures/Public")
            ?? bundle.url(forResource: "manifest", withExtension: "json")
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: try XCTUnwrap(url)))
    }

    private func image(for fixture: Manifest.Fixture) throws -> UIImage {
        try XCTUnwrap(UIImage(named: fixture.asset), "Missing public fixture asset \(fixture.asset)")
    }

    // MARK: - Deterministic transforms

    private func transform(_ image: UIImage, named name: String) throws -> UIImage {
        switch name {
        case "orientation_metadata":
            return try orientationMetadataFixture(image)
        case "jpeg_0_72":
            return try XCTUnwrap(UIImage(data: try XCTUnwrap(PhotoStore.prepare(image).image.jpegData(compressionQuality: 0.72))))
        case "brightness_minus_0_08":
            return try colorTransform(image, brightness: -0.08, contrast: 1)
        case "contrast_plus_0_08":
            return try colorTransform(image, brightness: 0, contrast: 1.08)
        case "translation_2_percent":
            return drawTransform(image, scale: 1, angle: 0, dx: image.size.width * 0.02, dy: image.size.height * -0.02)
        case "rotation_minus_2_degrees": return drawTransform(image, scale: 1, angle: -2, dx: 0, dy: 0)
        case "rotation_plus_2_degrees": return drawTransform(image, scale: 1, angle: 2, dx: 0, dy: 0)
        case "valid_crop_3_percent": return drawTransform(image, scale: 1.03, angle: 0, dx: 0, dy: 0)
        case "scale_minus_8_percent": return drawTransform(image, scale: 0.92, angle: 0, dx: 0, dy: 0)
        case "scale_minus_5_percent": return drawTransform(image, scale: 0.95, angle: 0, dx: 0, dy: 0)
        case "scale_minus_3_percent": return drawTransform(image, scale: 0.97, angle: 0, dx: 0, dy: 0)
        case "scale_plus_3_percent": return drawTransform(image, scale: 1.03, angle: 0, dx: 0, dy: 0)
        case "scale_plus_5_percent": return drawTransform(image, scale: 1.05, angle: 0, dx: 0, dy: 0)
        case "scale_plus_8_percent": return drawTransform(image, scale: 1.08, angle: 0, dx: 0, dy: 0)
        default: throw FixtureError.unknownTransformation(name)
        }
    }

    private func invalidTransform(_ image: UIImage, named name: String) throws -> UIImage {
        switch name {
        case "crop": return drawTransform(image, scale: 2.2, angle: 0, dx: 0, dy: image.size.height * 0.35)
        case "occlusion":
            return fixtureRenderer(size: image.size).image { context in
                image.draw(at: .zero)
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: image.size.height * 0.25, width: image.size.width, height: image.size.height * 0.55))
            }
        case "pose": return image
        case "exposure":
            return UIGraphicsImageRenderer(size: image.size).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: image.size))
            }
        default: throw FixtureError.unknownTransformation(name)
        }
    }

    private func drawTransform(
        _ input: UIImage,
        scale: CGFloat,
        angle: CGFloat,
        dx: CGFloat,
        dy: CGFloat
    ) -> UIImage {
        let image = PhotoStore.prepare(input).image
        return fixtureRenderer(size: image.size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            let cg = context.cgContext
            cg.translateBy(x: image.size.width / 2 + dx, y: image.size.height / 2 + dy)
            cg.rotate(by: angle * .pi / 180)
            cg.scaleBy(x: scale, y: scale)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }

    private func fixtureRenderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    private func colorTransform(_ input: UIImage, brightness: Float, contrast: Float) throws -> UIImage {
        let image = PhotoStore.prepare(input).image
        let source = try XCTUnwrap(CIImage(image: image))
        let filter = CIFilter(name: "CIColorControls")!
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        let output = try XCTUnwrap(filter.outputImage)
        let cg = try XCTUnwrap(CIContext(options: nil).createCGImage(output, from: output.extent))
        return UIImage(cgImage: cg)
    }

    private func orientationMetadataFixture(_ input: UIImage) throws -> UIImage {
        let prepared = PhotoStore.prepare(input).image
        let original = CIImage(cgImage: try XCTUnwrap(prepared.cgImage))
        let rotated = original.oriented(.left)
        let normalized = rotated.transformed(by: CGAffineTransform(
            translationX: -rotated.extent.origin.x,
            y: -rotated.extent.origin.y
        ))
        let cg = try XCTUnwrap(CIContext(options: nil).createCGImage(normalized, from: normalized.extent))
        // The encoded pixels are left-rotated while metadata rotates them right,
        // producing the same displayed image after PhotoStore normalization.
        return UIImage(cgImage: cg, scale: 1, orientation: .right)
    }

    // MARK: - Reports

    private func attachDebug(_ value: ProcessedPose, name: String) {
        let mask = value.debug.mask
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: mask.width, height: mask.height),
            format: format
        ).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
            UIColor.white.setFill()
            for y in 0..<mask.height {
                for x in 0..<mask.width where mask.isForeground(x: x, y: y) {
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            let cg = context.cgContext
            cg.setLineWidth(2)
            cg.setStrokeColor(UIColor.systemRed.cgColor)
            for line in value.debug.samplingLines {
                cg.move(to: CGPoint(x: CGFloat(line.startX), y: CGFloat(line.startY)))
                cg.addLine(to: CGPoint(x: CGFloat(line.endX), y: CGFloat(line.endY)))
                cg.strokePath()
            }
            UIColor.systemGreen.setFill()
            for landmark in value.extracted.landmarks {
                let x = CGFloat(landmark.x) * CGFloat(mask.width - 1)
                let y = CGFloat(landmark.y) * CGFloat(mask.height - 1)
                context.fill(CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
            }
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "\(name)-mask-landmarks-sampling"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachReport(
        fixture: String,
        availability: AnalysisAvailability,
        signals: VisualSignalSet,
        duration: Double,
        failures: [String: String],
        processed: [ProcessedPose] = []
    ) {
        let literalSignals = Dictionary(uniqueKeysWithValues: signals.deltas.map { delta in
            let signal: DirectionalSignal = delta.normalizedDelta == 0
                ? .neutral
                : (delta.normalizedDelta > 0 ? .minimalPositive : .minimalNegative)
            return (delta.region.rawValue, signal)
        })
        let interpreted = InterpretedSignals(
            scanCount: 4,
            weeksTracked: 3,
            reliabilityTier: .buildingTrend,
            goal: .maintain,
            overallConfidence: .low,
            signals: literalSignals,
            taperSignal: .unclear,
            proportionSignal: .unclear,
            measurementAlignment: [:],
            recompositionPatterns: [],
            scanQualityNotes: [],
            signalConflicts: [],
            contextNotes: [],
            analysisAvailability: availability,
            thresholdSetIdentifier: AnalysisThresholdSet.engineeringV1.identifier,
            thresholdsValidated: false
        )
        let wording = InsightEngine.templateFallback(signals: interpreted)
        let report = AnalysisRunReport(
            fixtureIdentifier: fixture,
            generatedAt: Date(),
            metadata: AnalysisAlgorithmMetadata(
                analysisVersion: 4,
                bodyPoseRevision: BodyPoseExtractor.bodyPoseRevision,
                personSegmentationRevision: SilhouetteAnalyzer.personSegmentationRevision,
                operatingSystemVersion: UIDevice.current.systemVersion,
                thresholdSetIdentifier: AnalysisThresholdSet.engineeringV1.identifier
            ),
            availability: availability,
            regionalComparisons: signals.regionalComparisons ?? [],
            signals: literalSignals,
            headline: wording.headline,
            processingDurationSeconds: duration,
            failures: failures,
            poseFeatures: processed.flatMap { $0.profile.regionFeatures ?? [] },
            poseMatchScores: Dictionary(uniqueKeysWithValues: processed.compactMap {
                guard let score = $0.extracted.poseMatchScore else { return nil }
                return ($0.fixture.pose.rawValue, score)
            }),
            stageTimingsSeconds: Dictionary(uniqueKeysWithValues: processed.map {
                ("\($0.fixture.pose.rawValue)_full_pipeline", $0.processingDurationSeconds)
            }).merging(["complete_fixture": duration]) { _, latest in latest },
            wording: wording
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "\(fixture)-analysis-report.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func analysis(
        profiles: [SilhouetteProfile],
        week: Int,
        signals: VisualSignalSet = VisualSignalSet(deltas: [], fatLossSignals: nil, reliabilityTier: .baseline)
    ) -> ScanAnalysis {
        let quality = QualityGateResult(verdict: .pass, issues: [], blurScore: 0, brightnessScore: 0.5, coverageScore: 1, regionalCoverage: [:])
        return ScanAnalysis(
            id: UUID(),
            analysisVersion: 4,
            analyzedAt: Date(timeIntervalSince1970: Double(week * 7 * 86_400)),
            qualityResult: quality,
            extractedPoses: [],
            silhouetteProfiles: profiles,
            visualSignals: signals,
            smoothedSignals: SmoothedSignalSet(smoothedDeltas: [:], smoothedTaperDelta: 0, smoothedProportionDelta: 0, reliabilityTier: .baseline, scanCount: week + 1),
            confidence: ConfidenceScore(overall: .low, rawScore: 0, regionalCoverage: [:], poseMatchScore: 0, lightingConsistency: 0, measurementAgreement: 0),
            interpretedSignals: InterpretedSignals(scanCount: week + 1, weeksTracked: week, reliabilityTier: .baseline, goal: .maintain, overallConfidence: .low, signals: [:], taperSignal: .unclear, proportionSignal: .unclear, measurementAlignment: [:], recompositionPatterns: [], scanQualityNotes: [], signalConflicts: [], contextNotes: [])
        )
    }

    private enum FixtureError: Error {
        case unknownTransformation(String)
        case processing(fixture: String, pose: String, reason: String, landmarks: String)
    }
}
