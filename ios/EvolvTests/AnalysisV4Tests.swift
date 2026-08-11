import XCTest
@testable import Evolv

final class AnalysisV4Tests: XCTestCase {
    func testPersonAlignedExtractionIsTranslationScaleAndRotationStable() throws {
        let baseline = try syntheticProfile(scale: 1, angleDegrees: 0, translation: (0, 0))
        let fixtures = [
            try syntheticProfile(scale: 1, angleDegrees: 0, translation: (35, -20)),
            try syntheticProfile(scale: 1.08, angleDegrees: 0, translation: (-15, 10)),
            try syntheticProfile(scale: 0.92, angleDegrees: 0, translation: (20, 15)),
            try syntheticProfile(scale: 1, angleDegrees: 2, translation: (0, 0)),
            try syntheticProfile(scale: 1, angleDegrees: -2, translation: (0, 0))
        ]

        for fixture in fixtures {
            for region in [BodyRegion.shoulders, .chest, .waist, .arms] {
                XCTAssertEqual(
                    feature(region, in: fixture),
                    feature(region, in: baseline),
                    accuracy: AnalysisThresholdSet.engineeringV1.stableBand(for: region),
                    "\(region.rawValue) changed under a valid geometric transform"
                )
            }
        }
    }

    func testSyntheticTorsoAndArmDimensionsRecoveredWithinOneMaskPixel() throws {
        let result = try syntheticProfile(scale: 1, angleDegrees: 0, translation: (0, 0))
        let reference = try XCTUnwrap(result.torsoReferencePixels)
        XCTAssertEqual(feature(.chest, in: result) * reference, 101, accuracy: 1)
        XCTAssertEqual(feature(.waist, in: result) * reference, 101, accuracy: 1)
        XCTAssertEqual(feature(.arms, in: result) * reference, 21, accuracy: 1)
    }

    func testPoseMatchUsesPersonAlignedGeometry() throws {
        let baseline = syntheticFixture(scale: 1, angleDegrees: 0, translation: (0, 0)).pose
        let transformed = syntheticFixture(scale: 1.08, angleDegrees: 2, translation: (30, -18)).pose
        let changedArms = moveLandmarks(transformed, joints: ["leftElbow", "leftWrist"], dx: 0.12, dy: 0)

        XCTAssertGreaterThan(try XCTUnwrap(NormalizationEngine.computePoseMatchScore(a: baseline, b: transformed)), 0.98)
        XCTAssertLessThan(try XCTUnwrap(NormalizationEngine.computePoseMatchScore(a: baseline, b: changedArms)), 0.85)
    }

    func testStableRegionsRemainPresentWithZeroDelta() {
        let baseline = analysis(profiles: requiredProfiles())
        let result = VisualSignalEngine.compute(
            currentProfiles: requiredProfiles(match: 0.99),
            allScanAnalyses: [baseline]
        )

        XCTAssertEqual(result.deltas.count, 4)
        XCTAssertTrue(result.deltas.allSatisfy { $0.normalizedDelta == 0 })
        XCTAssertTrue(result.regionalComparisons?.allSatisfy { $0.status == .stable } == true)
    }

    func testKnownCameraConfigurationChangeExcludesAffectedPoseEvidence() {
        var baseline = analysis(profiles: requiredProfiles())
        baseline.captureCameraMetadata = Dictionary(uniqueKeysWithValues: Pose.required.map {
            ($0.rawValue, cameraMetadata(position: .rear, lensType: "wide"))
        })
        let currentMetadata = Dictionary(uniqueKeysWithValues: Pose.required.map {
            ($0, cameraMetadata(position: .front, lensType: "wide"))
        })

        let result = VisualSignalEngine.compute(
            currentProfiles: requiredProfiles(match: 0.99),
            allScanAnalyses: [baseline],
            currentCameraMetadata: currentMetadata
        )

        XCTAssertTrue(result.regionalComparisons?.allSatisfy { $0.status == .unavailable } == true)
        XCTAssertTrue(result.regionalComparisons?.flatMap(\.contributions).contains {
            $0.reason == "camera_configuration_changed"
        } == true)
        XCTAssertTrue(result.deltas.isEmpty)
    }

    func testLegacyUnknownCameraMetadataDoesNotRejectOtherwiseComparableEvidence() {
        let result = VisualSignalEngine.compute(
            currentProfiles: requiredProfiles(match: 0.99),
            allScanAnalyses: [analysis(profiles: requiredProfiles())],
            currentCameraMetadata: Dictionary(uniqueKeysWithValues: Pose.required.map {
                ($0, cameraMetadata(position: .front, lensType: "wide"))
            })
        )

        XCTAssertTrue(result.regionalComparisons?.allSatisfy { $0.status == .stable } == true)
    }

    func testPoseBelowMinimumMatchIsExcluded() {
        let baseline = analysis(profiles: requiredProfiles())
        var current = requiredProfiles(match: 0.99)
        current[current.firstIndex(where: { $0.pose == .front })!].poseMatchScore = 0.84
        let result = VisualSignalEngine.compute(currentProfiles: current, allScanAnalyses: [baseline])

        let shoulders = result.regionalComparisons?.first { $0.region == .shoulders }
        XCTAssertEqual(shoulders?.status, .unavailable)
        XCTAssertTrue(shoulders?.contributions.contains { $0.reason == "pose_not_comparable" } == true)
    }

    func testMissingPoseMatchCannotDefaultToComparable() {
        let result = VisualSignalEngine.compute(
            currentProfiles: requiredProfiles(match: nil),
            allScanAnalyses: [analysis(profiles: requiredProfiles())]
        )

        XCTAssertTrue(result.regionalComparisons?.allSatisfy { $0.status == .unavailable } == true)
        XCTAssertTrue(result.deltas.isEmpty)
        XCTAssertTrue(result.regionalComparisons?.flatMap(\.contributions).contains {
            $0.reason == "pose_match_unavailable"
        } == true)
    }

    func testCrossPoseDisagreementBecomesUnavailable() {
        let baseline = analysis(profiles: requiredProfiles())
        let current = requiredProfiles(match: 0.99, overrides: [
            .front: [.waist: 0.318],
            .side: [.waist: 0.282]
        ])
        let result = VisualSignalEngine.compute(currentProfiles: current, allScanAnalyses: [baseline])
        let waist = result.regionalComparisons?.first { $0.region == .waist }

        XCTAssertEqual(waist?.status, .unavailable)
        XCTAssertEqual(waist?.reason, "cross_pose_conflict")
        XCTAssertFalse(result.deltas.contains { $0.region == .waist })
    }

    func testMissingEvidenceNeverBecomesStableOrFavorable() {
        var baselineProfiles = requiredProfiles()
        baselineProfiles[baselineProfiles.firstIndex(where: { $0.pose == .side })!].regionFeatures?.removeAll { $0.region == .chest }
        let result = VisualSignalEngine.compute(
            currentProfiles: requiredProfiles(match: 0.99),
            allScanAnalyses: [analysis(profiles: baselineProfiles)]
        )
        let chest = result.regionalComparisons?.first { $0.region == .chest }

        XCTAssertEqual(chest?.status, .unavailable)
        XCTAssertNil(chest?.normalizedDelta)
        XCTAssertFalse(result.deltas.contains { $0.region == .chest })
    }

    func testPhysicalDirectionDoesNotChangeWithGoal() {
        let fatLoss = interpreted(goal: .fatLoss, waistDelta: -0.02)
        let muscleGain = interpreted(goal: .muscleGain, waistDelta: -0.02)

        XCTAssertEqual(fatLoss.signals[BodyRegion.waist.rawValue], .moderateNegative)
        XCTAssertEqual(muscleGain.signals[BodyRegion.waist.rawValue], .moderateNegative)
        XCTAssertEqual(fatLoss.goalAlignments?[BodyRegion.waist.rawValue], .favorable)
        XCTAssertEqual(muscleGain.goalAlignments?[BodyRegion.waist.rawValue], .notApplicable)
        XCTAssertEqual(fatLoss.signalSemanticsVersion, 2)
    }

    func testOptionalPosesCannotAlterAnalyticalOutput() throws {
        let baseline = analysis(profiles: requiredProfiles())
        let required = VisualSignalEngine.compute(
            currentProfiles: requiredProfiles(match: 0.99),
            allScanAnalyses: [baseline]
        )
        var withOptional = requiredProfiles(match: 0.99)
        withOptional.append(profile(pose: .frontDoubleBicep, values: [.arms: 9], match: 0))
        withOptional.append(profile(pose: .legs, values: [.thighs: 9], match: 0))
        let optional = VisualSignalEngine.compute(currentProfiles: withOptional, allScanAnalyses: [baseline])

        XCTAssertEqual(try encoded(required.regionalComparisons), try encoded(optional.regionalComparisons))
        XCTAssertFalse(optional.deltas.contains { $0.region == .thighs })
    }

    func testUnsafeCloudWordingIsRejected() {
        let signals = interpreted(goal: .fatLoss, waistDelta: -0.02)
        let unsafe = GeneratedInsight(
            headline: "Fat loss detected",
            detail: "Your waist decreased.",
            caveat: "",
            regionNotes: [:],
            momentum: "Changed",
            confidence: .low,
            generatedAt: Date(timeIntervalSince1970: 0),
            source: .llm
        )
        XCTAssertFalse(InsightSafetyValidator.isSafe(unsafe, for: signals))

        let contradictory = GeneratedInsight(
            headline: "Visual comparison",
            detail: "Waist silhouette increased.",
            caveat: "Visual evidence only.",
            regionNotes: [:],
            momentum: "Changed",
            confidence: .low,
            generatedAt: Date(timeIntervalSince1970: 0),
            source: .llm
        )
        XCTAssertFalse(InsightSafetyValidator.isSafe(contradictory, for: signals))
    }

    func testVersionThreeAnalysisDecodesWithoutVersionFourFields() throws {
        var value = analysis(profiles: requiredProfiles())
        value.analysisVersion = 3
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object.removeValue(forKey: "algorithmMetadata")
        var visual = try XCTUnwrap(object["visualSignals"] as? [String: Any])
        visual.removeValue(forKey: "regionalComparisons")
        object["visualSignals"] = visual

        let decoded = try JSONDecoder().decode(
            ScanAnalysis.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.analysisVersion, 3)
        XCTAssertNil(decoded.algorithmMetadata)
        XCTAssertNil(decoded.visualSignals.regionalComparisons)
    }

    // MARK: - Synthetic geometry

    private func syntheticProfile(
        scale: Float,
        angleDegrees: Float,
        translation: (Float, Float)
    ) throws -> SilhouetteProfile {
        let fixture = syntheticFixture(scale: scale, angleDegrees: angleDegrees, translation: translation)
        return try SilhouetteAnalyzer.analyze(mask: fixture.mask, extractedPose: fixture.pose)
    }

    private func syntheticFixture(
        scale: Float,
        angleDegrees: Float,
        translation: (Float, Float)
    ) -> (mask: BinaryPersonMask, pose: ExtractedPose) {
        let size = 600
        let angle = angleDegrees * .pi / 180
        let down = AnalysisPoint(x: sin(angle), y: cos(angle))
        let cross = AnalysisPoint(x: cos(angle), y: -sin(angle))
        let shoulder = AnalysisPoint(x: 300 + translation.0, y: 160 + translation.1)
        let torsoLength: Float = 200 * scale
        let torsoWidth: Float = 100 * scale
        let armLength: Float = 145 * scale
        let armWidth: Float = 20 * scale
        let armOffset = torsoWidth / 2 + armWidth * 1.5

        func projection(_ point: AnalysisPoint, origin: AnalysisPoint, axis: AnalysisPoint) -> Float {
            let delta = point - origin
            return delta.x * axis.x + delta.y * axis.y
        }

        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let point = AnalysisPoint(x: Float(x), y: Float(y))
                let along = projection(point, origin: shoulder, axis: down)
                let across = projection(point, origin: shoulder, axis: cross)
                let torso = along >= 0 && along <= torsoLength && abs(across) <= torsoWidth / 2
                let leftArm = along >= 0 && along <= armLength && abs(across + armOffset) <= armWidth / 2
                let rightArm = along >= 0 && along <= armLength && abs(across - armOffset) <= armWidth / 2
                if torso || leftArm || rightArm { pixels[y * size + x] = 255 }
            }
        }

        func point(down amount: Float, across amountAcross: Float) -> AnalysisPoint {
            shoulder + down * amount + cross * amountAcross
        }
        func landmark(_ joint: String, _ point: AnalysisPoint) -> NormalizedLandmark {
            NormalizedLandmark(
                joint: joint,
                x: point.x / Float(size - 1),
                y: point.y / Float(size - 1),
                confidence: 1
            )
        }
        let leftShoulder = point(down: 0, across: -armOffset)
        let rightShoulder = point(down: 0, across: armOffset)
        let landmarks = [
            landmark("leftShoulder", leftShoulder),
            landmark("rightShoulder", rightShoulder),
            landmark("leftHip", point(down: torsoLength, across: -torsoWidth * 0.2)),
            landmark("rightHip", point(down: torsoLength, across: torsoWidth * 0.2)),
            landmark("leftElbow", point(down: armLength * 0.72, across: -armOffset)),
            landmark("rightElbow", point(down: armLength * 0.72, across: armOffset)),
            landmark("leftWrist", point(down: armLength, across: -armOffset)),
            landmark("rightWrist", point(down: armLength, across: armOffset))
        ]
        let pose = ExtractedPose(
            scanId: UUID(),
            pose: .front,
            landmarks: landmarks,
            bodyHeightPx: torsoLength,
            poseMatchScore: nil
        )
        return (BinaryPersonMask(width: size, height: size, pixels: pixels), pose)
    }

    private func moveLandmarks(
        _ pose: ExtractedPose,
        joints: Set<String>,
        dx: Float,
        dy: Float
    ) -> ExtractedPose {
        var copy = pose
        copy.landmarks = pose.landmarks.map { value in
            guard joints.contains(value.joint) else { return value }
            return NormalizedLandmark(
                joint: value.joint,
                x: value.x + dx,
                y: value.y + dy,
                confidence: value.confidence
            )
        }
        return copy
    }

    // MARK: - Analysis fixtures

    private func requiredProfiles(
        match: Float? = nil,
        overrides: [Pose: [BodyRegion: Float]] = [:]
    ) -> [SilhouetteProfile] {
        [Pose.front, .side, .back].map { pose in
            let defaults: [BodyRegion: Float] = [
                .shoulders: 0.50, .chest: 0.42, .waist: 0.30, .arms: 0.12
            ]
            return profile(pose: pose, values: defaults.merging(overrides[pose] ?? [:]) { _, new in new }, match: match)
        }
    }

    private func profile(
        pose: Pose,
        values: [BodyRegion: Float],
        match: Float?
    ) -> SilhouetteProfile {
        let allowed: Set<BodyRegion>
        switch pose {
        case .front: allowed = [.shoulders, .chest, .waist, .arms]
        case .side: allowed = [.chest, .waist, .arms]
        case .back: allowed = [.shoulders, .waist, .arms]
        default: allowed = Set(values.keys)
        }
        let features = values.compactMap { region, value -> PoseRegionFeature? in
            guard allowed.contains(region) else { return nil }
            return PoseRegionFeature(
                pose: pose,
                region: region,
                normalizedValue: value,
                source: region == .arms ? .limbCrossSection : .torsoCrossSection,
                evidenceReason: nil
            )
        }
        return SilhouetteProfile(
            scanId: UUID(),
            pose: pose,
            widthAtY: [],
            shoulderWidthRatio: values[.shoulders] ?? 0,
            chestWidthRatio: values[.chest] ?? 0,
            waistWidthRatio: values[.waist] ?? 0,
            armMidWidthRatio: values[.arms] ?? 0,
            thighMidWidthRatio: values[.thighs] ?? 0,
            taperIndex: 0,
            chestToWaistRatio: 1,
            shoulderToWaistRatio: 1,
            hipWidthRatio: nil,
            lowerTorsoWidthRatio: values[.waist] ?? 0,
            supportedRegions: features.map(\.region),
            regionFeatures: features,
            torsoReferencePixels: 200,
            poseMatchScore: match
        )
    }

    private func feature(_ region: BodyRegion, in profile: SilhouetteProfile) -> Float {
        profile.regionFeatures?.first { $0.region == region }?.normalizedValue ?? -1
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

    private func interpreted(goal: FitnessGoal, waistDelta: Float) -> InterpretedSignals {
        let visual = VisualSignalSet(
            deltas: [RegionalDelta(region: .waist, normalizedDelta: waistDelta, fromScanCount: 2)],
            fatLossSignals: nil,
            reliabilityTier: .earlyStage,
            regionalComparisons: []
        )
        let smoothed = SmoothedSignalSet(
            smoothedDeltas: [BodyRegion.waist.rawValue: waistDelta],
            smoothedTaperDelta: 0,
            smoothedProportionDelta: 0,
            reliabilityTier: .earlyStage,
            scanCount: 2
        )
        var profile = UserProfile()
        profile.goal = goal
        return SignalInterpreter.interpret(
            smoothed: smoothed,
            visualSignals: visual,
            measurements: [],
            profile: profile,
            recompositionPatterns: [],
            qualityResult: quality(),
            assessments: [:],
            analysisAvailability: .comparable,
            allAnalyses: [],
            scanContext: nil,
            thresholds: .engineeringV1,
            now: Date(timeIntervalSince1970: 0)
        )
    }

    private func analysis(profiles: [SilhouetteProfile]) -> ScanAnalysis {
        ScanAnalysis(
            id: UUID(),
            analysisVersion: 4,
            analyzedAt: Date(timeIntervalSince1970: 0),
            qualityResult: quality(),
            extractedPoses: [],
            silhouetteProfiles: profiles,
            visualSignals: VisualSignalSet(deltas: [], fatLossSignals: nil, reliabilityTier: .baseline),
            smoothedSignals: SmoothedSignalSet(
                smoothedDeltas: [:],
                smoothedTaperDelta: 0,
                smoothedProportionDelta: 0,
                reliabilityTier: .baseline,
                scanCount: 1
            ),
            confidence: ConfidenceScore(
                overall: .low,
                rawScore: 0,
                regionalCoverage: [:],
                poseMatchScore: 0,
                lightingConsistency: 0,
                measurementAgreement: 0,
                hasSufficientEvidence: false
            ),
            interpretedSignals: InterpretedSignals(
                scanCount: 1,
                weeksTracked: 0,
                reliabilityTier: .baseline,
                goal: .maintain,
                overallConfidence: .low,
                signals: [:],
                taperSignal: .unclear,
                proportionSignal: .unclear,
                measurementAlignment: [:],
                recompositionPatterns: [],
                scanQualityNotes: [],
                signalConflicts: [],
                contextNotes: []
            )
        )
    }

    private func quality() -> QualityGateResult {
        QualityGateResult(
            verdict: .pass,
            issues: [],
            blurScore: 0,
            brightnessScore: 0.5,
            coverageScore: 1,
            regionalCoverage: [:]
        )
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
