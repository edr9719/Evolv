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

    func testKnownCameraCannotCompareAgainstUnknownCameraMetadata() {
        let result = VisualSignalEngine.compute(
            currentProfiles: requiredProfiles(match: 0.99),
            allScanAnalyses: [analysis(profiles: requiredProfiles())],
            currentCameraMetadata: Dictionary(uniqueKeysWithValues: Pose.required.map {
                ($0, cameraMetadata(position: .front, lensType: "wide"))
            })
        )

        XCTAssertTrue(result.regionalComparisons?.allSatisfy { $0.status == .unavailable } == true)
        XCTAssertTrue(result.regionalComparisons?.flatMap(\.contributions).contains {
            $0.reason == "camera_configuration_unknown"
        } == true)
        XCTAssertTrue(result.deltas.isEmpty)
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

    func testOptionalPoseProducesSeparateSamePoseEvidence() throws {
        var baselineProfiles = requiredProfiles()
        baselineProfiles.append(profile(
            pose: .frontDoubleBicep,
            values: [.shoulders: 0.50, .chest: 0.42, .waist: 0.30, .arms: 0.12],
            match: nil
        ))
        var currentProfiles = requiredProfiles(match: 0.99)
        currentProfiles.append(profile(
            pose: .frontDoubleBicep,
            values: [.shoulders: 0.50, .chest: 0.42, .waist: 0.30, .arms: 0.14],
            match: 0.99
        ))

        let result = VisualSignalEngine.compute(
            currentProfiles: currentProfiles,
            allScanAnalyses: [analysis(profiles: baselineProfiles)]
        )
        let flexed = try XCTUnwrap(result.poseComparisons?.first { $0.pose == .frontDoubleBicep })
        let arms = try XCTUnwrap(flexed.regions.first { $0.region == .arms })

        XCTAssertEqual(flexed.availability, .comparable)
        XCTAssertEqual(arms.status, .increase)
        XCTAssertEqual(arms.normalizedDelta ?? 0, 0.14 / 0.12 - 1, accuracy: 0.0001)
        XCTAssertTrue(result.regionalComparisons?.allSatisfy { $0.status == .stable } == true)
        XCTAssertFalse(result.deltas.contains { $0.region == .thighs })
    }

    func testEveryPoseRegionHasAStableSyntheticSamePoseContract() throws {
        for pose in Pose.allCases {
            let values = Dictionary(uniqueKeysWithValues: analyticalRegions(for: pose).map { region in
                (region, syntheticValue(for: region))
            })
            let comparison = VisualSignalEngine.comparePosePair(
                baselineProfile: profile(pose: pose, values: values, match: nil),
                currentProfile: profile(pose: pose, values: values, match: 0.99)
            )

            XCTAssertEqual(comparison.availability, .comparable, pose.rawValue)
            XCTAssertEqual(Set(comparison.regions.map(\.region)), Set(analyticalRegions(for: pose)), pose.rawValue)
            XCTAssertTrue(comparison.regions.allSatisfy {
                $0.status == .stable && $0.normalizedDelta == 0
            }, pose.rawValue)
        }
    }

    func testEveryPoseRegionKeepsChangeInsideItsExactPose() throws {
        for pose in Pose.allCases {
            let regions = analyticalRegions(for: pose)
            let baselineValues = Dictionary(uniqueKeysWithValues: regions.map { region in
                (region, syntheticValue(for: region))
            })
            for changedRegion in regions {
                var currentValues = baselineValues
                currentValues[changedRegion] = syntheticValue(for: changedRegion) * 1.05
                let comparison = VisualSignalEngine.comparePosePair(
                    baselineProfile: profile(pose: pose, values: baselineValues, match: nil),
                    currentProfile: profile(pose: pose, values: currentValues, match: 0.99)
                )

                XCTAssertEqual(
                    comparison.regions.first { $0.region == changedRegion }?.status,
                    .increase,
                    "\(pose.rawValue)/\(changedRegion.rawValue)"
                )
                XCTAssertTrue(comparison.regions.filter { $0.region != changedRegion }.allSatisfy {
                    $0.status == .stable
                }, "\(pose.rawValue)/\(changedRegion.rawValue)")
            }
        }
    }

    func testCrossPoseSubstitutionAndContractionChangeAreUnavailable() {
        let relaxed = profile(
            pose: .front,
            values: [.shoulders: 0.50, .chest: 0.42, .waist: 0.30, .arms: 0.12],
            match: nil
        )
        let contracted = profile(
            pose: .frontDoubleBicep,
            values: [.shoulders: 0.50, .chest: 0.42, .waist: 0.30, .arms: 0.12],
            match: 0.99
        )

        let comparison = VisualSignalEngine.comparePosePair(
            baselineProfile: relaxed,
            currentProfile: contracted
        )

        XCTAssertEqual(comparison.availability, .partialEvidence)
        XCTAssertEqual(comparison.reason, "pose_mismatch")
        XCTAssertTrue(comparison.regions.isEmpty)
    }

    func testLegFixtureRecoversThighThicknessWithoutShoulders() throws {
        let fixture = syntheticLegFixture()
        let result = try SilhouetteAnalyzer.analyze(mask: fixture.mask, extractedPose: fixture.pose)
        let reference = try XCTUnwrap(result.torsoReferencePixels)

        XCTAssertEqual(result.supportedRegions, [.thighs])
        XCTAssertEqual(feature(.thighs, in: result) * reference, 31, accuracy: 1)
    }

    func testLegFixtureAcceptsOneBoundedWeakHipButRejectsWeakBilateralEvidence() throws {
        let bounded = syntheticLegFixture(leftHipConfidence: 0.19, rightHipConfidence: 0.32)
        XCTAssertNoThrow(try SilhouetteAnalyzer.analyze(mask: bounded.mask, extractedPose: bounded.pose))

        let weakAverage = syntheticLegFixture(leftHipConfidence: 0.19, rightHipConfidence: 0.20)
        XCTAssertThrowsError(try SilhouetteAnalyzer.analyze(
            mask: weakAverage.mask,
            extractedPose: weakAverage.pose
        ))
        let belowFloor = syntheticLegFixture(leftHipConfidence: 0.17, rightHipConfidence: 0.40)
        XCTAssertThrowsError(try SilhouetteAnalyzer.analyze(
            mask: belowFloor.mask,
            extractedPose: belowFloor.pose
        ))
    }

    func testLegFixtureRecoversWhenVisionSwapsOnlyHipLabels() throws {
        let fixture = syntheticLegFixture(swapHipLabels: true)
        let result = try SilhouetteAnalyzer.analyze(
            mask: fixture.mask,
            extractedPose: fixture.pose
        )
        let reference = try XCTUnwrap(result.torsoReferencePixels)

        XCTAssertEqual(result.supportedRegions, [.thighs])
        XCTAssertEqual(feature(.thighs, in: result) * reference, 31, accuracy: 1)
    }

    func testLowerBodyPoseMatchCanonicalizesBoundedSwappedHipLabels() throws {
        let baseline = syntheticLegFixture(
            leftHipConfidence: 0.19,
            rightHipConfidence: 0.32
        ).pose
        let swapped = syntheticLegFixture(
            leftHipConfidence: 0.19,
            rightHipConfidence: 0.32,
            swapHipLabels: true
        ).pose

        XCTAssertEqual(
            try XCTUnwrap(NormalizationEngine.computePoseMatchScore(a: baseline, b: swapped)),
            1,
            accuracy: 0.001
        )
        let weak = syntheticLegFixture(
            leftHipConfidence: 0.19,
            rightHipConfidence: 0.20
        ).pose
        XCTAssertNil(NormalizationEngine.computePoseMatchScore(a: baseline, b: weak))
    }

    func testSelectedPairRecomputesEvidenceForExactTwoScans() throws {
        let recipeID = UUID()
        let before = comparisonScan(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_000),
            recipeID: recipeID,
            pose: .front
        )
        let after = comparisonScan(
            id: UUID(),
            date: Date(timeIntervalSince1970: 2_000),
            recipeID: recipeID,
            pose: .front
        )
        var baselinePose = syntheticFixture(scale: 1, angleDegrees: 0, translation: (0, 0)).pose
        baselinePose.scanId = before.id
        var currentPose = baselinePose
        currentPose.scanId = after.id

        var beforeAnalysis = analysis(profiles: [profile(
            pose: .front,
            values: [.shoulders: 0.50, .chest: 0.42, .waist: 0.30, .arms: 0.12],
            match: nil
        )])
        beforeAnalysis.id = before.id
        beforeAnalysis.analysisVersion = AnalysisStore.currentAnalysisVersion
        beforeAnalysis.extractedPoses = [baselinePose]
        var afterAnalysis = analysis(profiles: [profile(
            pose: .front,
            values: [.shoulders: 0.50, .chest: 0.42, .waist: 0.30, .arms: 0.14],
            match: 0.10 // stale score against a different historical baseline
        )])
        afterAnalysis.id = after.id
        afterAnalysis.analysisVersion = AnalysisStore.currentAnalysisVersion
        afterAnalysis.extractedPoses = [currentPose]

        let comparison = ScanPairComparisonEngine.compare(
            before: before,
            after: after,
            beforeAnalysis: beforeAnalysis,
            afterAnalysis: afterAnalysis
        )
        let front = try XCTUnwrap(comparison.comparison(for: .front))
        let arms = try XCTUnwrap(front.regions.first { $0.region == .arms })

        XCTAssertEqual(comparison.availability, .comparable)
        XCTAssertEqual(arms.status, .increase)
        XCTAssertGreaterThan(try XCTUnwrap(arms.contributions.first?.poseMatchScore), 0.99)
        XCTAssertEqual(comparison.evidenceStrength(for: .front), .low)
        XCTAssertTrue(comparison.relaxedRegions.allSatisfy { $0.status == .unavailable })
    }

    func testSelectedPairRejectsDifferentCaptureRecipes() {
        let before = comparisonScan(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_000),
            recipeID: UUID(),
            pose: .front
        )
        let after = comparisonScan(
            id: UUID(),
            date: Date(timeIntervalSince1970: 2_000),
            recipeID: UUID(),
            pose: .front
        )

        let result = ScanPairComparisonEngine.compare(
            before: before,
            after: after,
            beforeAnalysis: nil,
            afterAnalysis: nil
        )

        XCTAssertEqual(result.availability, .partialEvidence)
        XCTAssertEqual(result.reason, "capture_recipe_changed")
        XCTAssertTrue(result.poseComparisons.isEmpty)
    }

    func testNarrativeCallsStableOnlyWhenEveryScopedRegionIsSupported() {
        let complete = pairComparison(relaxed: [
            regional(.shoulders, .stable, 0),
            regional(.chest, .stable, 0),
            regional(.waist, .stable, 0),
            regional(.arms, .stable, 0)
        ])
        let completeNarrative = ComparisonNarrativeEngine.make(
            comparison: complete,
            goal: .maintain
        )

        XCTAssertEqual(completeNarrative.status, .stable)
        XCTAssertEqual(completeNarrative.headline, "No meaningful visual change detected")
        XCTAssertEqual(completeNarrative.findings.count, 4)

        let limited = pairComparison(relaxed: [
            regional(.shoulders, .stable, 0),
            regional(.chest, .unavailable, nil)
        ])
        let limitedNarrative = ComparisonNarrativeEngine.make(
            comparison: limited,
            goal: .maintain
        )

        XCTAssertEqual(limitedNarrative.status, .limited)
        XCTAssertEqual(limitedNarrative.headline, "Supported regions remained stable")
        XCTAssertTrue(limitedNarrative.detail.contains("Unsupported regions were left unavailable"))
    }

    func testOptionalNarrativeIsUsefulButCannotChangeRelaxedConclusion() throws {
        let optional = PoseComparison(
            pose: .frontDoubleBicep,
            availability: .comparable,
            regions: [regional(.arms, .increase, 0.05, pose: .frontDoubleBicep)],
            reason: nil
        )
        let comparison = pairComparison(
            relaxed: [
                regional(.shoulders, .stable, 0),
                regional(.chest, .stable, 0),
                regional(.waist, .stable, 0),
                regional(.arms, .stable, 0)
            ],
            optional: [optional]
        )

        let overall = ComparisonNarrativeEngine.make(comparison: comparison, goal: .muscleGain)
        let relaxed = ComparisonNarrativeEngine.make(comparison: comparison, pose: .front, goal: .muscleGain)
        let flexed = ComparisonNarrativeEngine.make(
            comparison: comparison,
            pose: .frontDoubleBicep,
            goal: .muscleGain
        )

        XCTAssertEqual(overall.status, .differenceDetected)
        XCTAssertTrue(overall.headline.contains("optional-pose"))
        XCTAssertTrue(overall.findings.contains { $0.pose == .frontDoubleBicep && $0.region == .arms })
        XCTAssertEqual(relaxed.status, .stable)
        XCTAssertTrue(relaxed.findings.allSatisfy { $0.pose == nil })
        XCTAssertEqual(try XCTUnwrap(flexed.findings.first).goalAlignment, .favorable)
        XCTAssertTrue(flexed.detail.contains("5.0%"))
    }

    func testGoalChangesAlignmentButNeverPhysicalNarrativeDirection() throws {
        let comparison = pairComparison(relaxed: [regional(.waist, .decrease, -0.03)])
        let fatLoss = ComparisonNarrativeEngine.make(comparison: comparison, goal: .fatLoss)
        let muscleGain = ComparisonNarrativeEngine.make(comparison: comparison, goal: .muscleGain)
        let fatLossFinding = try XCTUnwrap(fatLoss.findings.first)
        let muscleGainFinding = try XCTUnwrap(muscleGain.findings.first)

        XCTAssertEqual(fatLossFinding.status, .decrease)
        XCTAssertEqual(muscleGainFinding.status, .decrease)
        XCTAssertEqual(fatLossFinding.normalizedDelta, muscleGainFinding.normalizedDelta)
        XCTAssertEqual(fatLossFinding.goalAlignment, .favorable)
        XCTAssertEqual(muscleGainFinding.goalAlignment, .notApplicable)
        XCTAssertTrue(fatLossFinding.statement.contains("decreased"))
        XCTAssertTrue(muscleGainFinding.statement.contains("decreased"))
    }

    func testUnavailableNarrativeNeverCreatesAChangeOrStableFinding() {
        var comparison = pairComparison(relaxed: [])
        comparison.availability = .partialEvidence
        comparison.reason = "capture_recipe_changed"

        let narrative = ComparisonNarrativeEngine.make(comparison: comparison, goal: .recomp)

        XCTAssertEqual(narrative.status, .unavailable)
        XCTAssertTrue(narrative.findings.isEmpty)
        XCTAssertTrue(narrative.detail.contains("different camera setups"))
        XCTAssertTrue(narrative.limitations.contains { $0.contains("No body-change claim") })
    }

    func testCloudWordingCannotAddUnsupportedRegionOrStrongerConfidence() {
        let signals = interpreted(goal: .fatLoss, waistDelta: 0)
        let unsupportedRegion = GeneratedInsight(
            headline: "Visual comparison",
            detail: "Arm silhouette thickness increased.",
            caveat: "Visual evidence only.",
            regionNotes: [:],
            momentum: "Stable",
            confidence: .low,
            generatedAt: Date(timeIntervalSince1970: 0),
            source: .llm
        )
        let strongerConfidence = GeneratedInsight(
            headline: "No meaningful visual change detected",
            detail: "Waist silhouette remained stable.",
            caveat: "Visual evidence only.",
            regionNotes: [BodyRegion.waist.rawValue: "Waist silhouette remained stable."],
            momentum: "Stable",
            confidence: .medium,
            generatedAt: Date(timeIntervalSince1970: 0),
            source: .llm
        )

        XCTAssertFalse(InsightSafetyValidator.isSafe(unsupportedRegion, for: signals))
        XCTAssertFalse(InsightSafetyValidator.isSafe(strongerConfidence, for: signals))
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

        let inventedMeasurement = GeneratedInsight(
            headline: "Arms changed",
            detail: "Your biceps grew by 1 inch.",
            caveat: "Visual evidence only.",
            regionNotes: [:],
            momentum: "Changed",
            confidence: .low,
            generatedAt: Date(timeIntervalSince1970: 0),
            source: .llm
        )
        XCTAssertFalse(InsightSafetyValidator.isSafe(inventedMeasurement, for: signals))
    }

    func testLegacyMeasurementDecodesWithoutInventingScanLink() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "date": 1000,
          "weightKg": 76.2,
          "arms": 35.5,
          "chest": 99.0,
          "waist": 80.0
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Evolv.Measurement.self, from: json)

        XCTAssertEqual(decoded.weightKg, 76.2)
        XCTAssertEqual(decoded.arms, 35.5)
        XCTAssertNil(decoded.scanID)
        XCTAssertNil(decoded.shoulders)
        XCTAssertNil(decoded.thighs)
    }

    func testSkippedMeasurementValuesRoundTripAsMissing() throws {
        let scanID = UUID()
        let original = Measurement(
            date: Date(timeIntervalSince1970: 1_000),
            weightKg: nil,
            arms: 36,
            chest: nil,
            waist: nil,
            shoulders: nil,
            thighs: nil,
            scanID: scanID
        )

        let decoded = try JSONDecoder().decode(Evolv.Measurement.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.scanID, scanID)
        XCTAssertNil(decoded.weightKg)
        XCTAssertEqual(decoded.arms, 36)
        XCTAssertNil(decoded.chest)
        XCTAssertNil(decoded.waist)
    }

    func testMeasurementComparisonUsesOnlyExplicitExactScanLinks() {
        let beforeID = UUID()
        let afterID = UUID()
        let unlinked = Measurement(
            date: Date(timeIntervalSince1970: 1_000),
            weightKg: 120,
            arms: 99,
            chest: nil,
            waist: nil,
            shoulders: nil,
            thighs: nil
        )
        let before = Measurement(
            date: Date(timeIntervalSince1970: 1_000),
            weightKg: nil,
            arms: 35,
            chest: nil,
            waist: 80,
            shoulders: nil,
            thighs: nil,
            scanID: beforeID
        )
        let after = Measurement(
            date: Date(timeIntervalSince1970: 2_000),
            weightKg: nil,
            arms: 36,
            chest: nil,
            waist: nil,
            shoulders: nil,
            thighs: nil,
            scanID: afterID
        )

        let result = MeasurementSignalEngine.compare(
            beforeScanID: beforeID,
            afterScanID: afterID,
            measurements: [unlinked, before, after]
        )

        let arms = result.results.first { $0.metric == .arms }
        let waist = result.results.first { $0.metric == .waist }
        let weight = result.results.first { $0.metric == .weight }
        XCTAssertEqual(arms?.status, .increase)
        XCTAssertEqual(arms?.delta, 1)
        XCTAssertEqual(waist?.status, .unavailable)
        XCTAssertNil(waist?.delta)
        XCTAssertEqual(weight?.status, .unavailable)
        XCTAssertTrue(result.hasBothMeasurements)
    }

    func testMeasurementDirectionIsLiteralAndVisualRelationshipStaysSeparate() throws {
        let beforeID = UUID()
        let afterID = UUID()
        let visual = ScanPairComparison(
            beforeScanID: beforeID,
            afterScanID: afterID,
            availability: .comparable,
            relaxedRegions: [
                regional(.arms, .increase, 0.02),
                regional(.waist, .increase, 0.02)
            ],
            poseComparisons: [],
            evidenceStrength: .medium,
            reason: nil
        )
        let before = Measurement(
            date: Date(timeIntervalSince1970: 1_000),
            weightKg: nil,
            arms: 35,
            chest: nil,
            waist: 80,
            shoulders: nil,
            thighs: nil,
            scanID: beforeID
        )
        let after = Measurement(
            date: Date(timeIntervalSince1970: 2_000),
            weightKg: nil,
            arms: 36,
            chest: nil,
            waist: 79,
            shoulders: nil,
            thighs: nil,
            scanID: afterID
        )

        let result = MeasurementSignalEngine.compare(
            beforeScanID: beforeID,
            afterScanID: afterID,
            measurements: [before, after],
            visualComparison: visual
        )
        let arms = try XCTUnwrap(result.results.first { $0.metric == .arms })
        let waist = try XCTUnwrap(result.results.first { $0.metric == .waist })

        XCTAssertEqual(arms.status, .increase)
        XCTAssertEqual(arms.visualRelationship, .sameDirection)
        XCTAssertEqual(waist.status, .decrease)
        XCTAssertEqual(waist.delta, -1)
        XCTAssertEqual(waist.visualRelationship, .differentResult)
        XCTAssertEqual(visual.evidenceStrength, .medium, "Measurement context must not alter visual evidence strength")
    }

    func testLongitudinalPatternRequiresTwoImmediateSupportedObservations() {
        let oneIncrease = [longitudinalObservation(.increase, index: 1)]
        let repeatedIncrease = [
            longitudinalObservation(.increase, index: 1),
            longitudinalObservation(.increase, index: 2)
        ]
        let interrupted = [
            longitudinalObservation(.increase, index: 1),
            longitudinalObservation(.unavailable, index: 2),
            longitudinalObservation(.increase, index: 3)
        ]

        XCTAssertEqual(LongitudinalVisualEngine.classify(oneIncrease), .emergingIncrease)
        XCTAssertEqual(LongitudinalVisualEngine.classify(repeatedIncrease), .repeatedIncrease)
        XCTAssertEqual(LongitudinalVisualEngine.classify(interrupted), .emergingIncrease)
        XCTAssertEqual(
            LongitudinalVisualEngine.classify([
                longitudinalObservation(.decrease, index: 1),
                longitudinalObservation(.increase, index: 2),
                longitudinalObservation(.increase, index: 3)
            ]),
            .repeatedIncrease,
            "An older direction must not override the two latest uninterrupted observations"
        )
    }

    func testFailedOptionalAttemptInterruptsRepeatedPattern() throws {
        let recipeID = UUID()
        let pose = Pose.frontDoubleBicep
        let scans = (0..<4).map { index in
            comparisonScan(
                id: UUID(),
                date: Date(timeIntervalSince1970: TimeInterval((index + 1) * 1_000)),
                recipeID: recipeID,
                pose: pose
            )
        }
        let analyses: [UUID: ScanAnalysis] = [
            scans[0].id: optionalAnalysis(scanID: scans[0].id, pose: pose, arms: 0.12),
            scans[1].id: optionalAnalysis(scanID: scans[1].id, pose: pose, arms: 0.14),
            // Scan 3 was captured but extraction failed, so it is deliberately
            // absent from the analysis map.
            scans[3].id: optionalAnalysis(scanID: scans[3].id, pose: pose, arms: 0.14)
        ]

        let summary = try XCTUnwrap(LongitudinalVisualEngine.evaluate(scans: scans, analyses: analyses))
        let arms = try XCTUnwrap(summary.optionalFindings.first {
            $0.pose == pose && $0.region == .arms
        })

        XCTAssertEqual(arms.observations.map(\.status), [.increase, .unavailable, .increase])
        XCTAssertEqual(arms.status, .emergingIncrease)
    }

    func testLongitudinalStableAndMixedAreNotConfused() {
        XCTAssertEqual(
            LongitudinalVisualEngine.classify([longitudinalObservation(.stable, index: 1)]),
            .insufficientEvidence
        )
        XCTAssertEqual(
            LongitudinalVisualEngine.classify([
                longitudinalObservation(.stable, index: 1),
                longitudinalObservation(.stable, index: 2)
            ]),
            .repeatedStable
        )
        XCTAssertEqual(
            LongitudinalVisualEngine.classify([
                longitudinalObservation(.increase, index: 1),
                longitudinalObservation(.decrease, index: 2)
            ]),
            .mixed
        )
    }

    func testCurrentSignalIsNotAveragedWithOlderBaselineDeltas() {
        var prior = analysis(profiles: requiredProfiles())
        prior.visualSignals = VisualSignalSet(
            deltas: [RegionalDelta(region: .waist, normalizedDelta: 0.20, fromScanCount: 2)],
            fatLossSignals: nil,
            reliabilityTier: .earlyStage
        )
        let current = VisualSignalSet(
            deltas: [RegionalDelta(region: .waist, normalizedDelta: -0.03, fromScanCount: 3)],
            fatLossSignals: nil,
            reliabilityTier: .earlyStage
        )

        let result = TrendSmoothingEngine.smooth(allAnalyses: [prior], currentVisualSignals: current)

        XCTAssertEqual(result.smoothedDeltas[BodyRegion.waist.rawValue], -0.03)
        XCTAssertEqual(result.scanCount, 2)
    }

    func testOptionalRepeatedPatternCannotCreateRelaxedLongitudinalClaim() throws {
        let relaxed = [BodyRegion.shoulders, .chest, .waist, .arms].map { region in
            LongitudinalVisualFinding(
                pose: nil,
                region: region,
                status: .repeatedStable,
                observations: [
                    longitudinalObservation(.stable, index: 1),
                    longitudinalObservation(.stable, index: 2)
                ]
            )
        }
        let optional = LongitudinalVisualFinding(
            pose: .frontDoubleBicep,
            region: .arms,
            status: .repeatedIncrease,
            observations: [
                longitudinalObservation(.increase, index: 1),
                longitudinalObservation(.increase, index: 2)
            ]
        )
        let summary = LongitudinalVisualSummary(
            scanCount: 3,
            findings: relaxed + [optional],
            thresholdSetIdentifier: AnalysisThresholdSet.engineeringV1.identifier,
            thresholdsValidated: false
        )

        let narrative = try XCTUnwrap(LongitudinalVisualEngine.narrative(for: summary))

        XCTAssertEqual(narrative.headline, "Repeated scans show visual stability")
        XCTAssertFalse(narrative.detail.localizedCaseInsensitiveContains("arm"))
        XCTAssertEqual(summary.optionalFindings.first?.status, .repeatedIncrease)
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
        XCTAssertNil(decoded.visualSignals.poseComparisons)
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

    private func syntheticLegFixture(
        leftHipConfidence: Float = 1,
        rightHipConfidence: Float = 1,
        swapHipLabels: Bool = false
    ) -> (mask: BinaryPersonMask, pose: ExtractedPose) {
        let width = 600
        let height = 650
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 100...500 {
            for x in 225...255 { pixels[y * width + x] = 255 }
            for x in 345...375 { pixels[y * width + x] = 255 }
        }
        func landmark(
            _ joint: String,
            x: Float,
            y: Float,
            confidence: Float = 1
        ) -> NormalizedLandmark {
            NormalizedLandmark(
                joint: joint,
                x: x / Float(width - 1),
                y: y / Float(height - 1),
                confidence: confidence
            )
        }
        let pose = ExtractedPose(
            scanId: UUID(),
            pose: .legs,
            landmarks: [
                landmark(
                    "leftHip",
                    x: swapHipLabels ? 360 : 240,
                    y: 100,
                    confidence: leftHipConfidence
                ),
                landmark(
                    "rightHip",
                    x: swapHipLabels ? 240 : 360,
                    y: 100,
                    confidence: rightHipConfidence
                ),
                landmark("leftKnee", x: 240, y: 300),
                landmark("rightKnee", x: 360, y: 300),
                landmark("leftAnkle", x: 240, y: 500),
                landmark("rightAnkle", x: 360, y: 500)
            ],
            bodyHeightPx: 400,
            poseMatchScore: nil
        )
        return (BinaryPersonMask(width: width, height: height, pixels: pixels), pose)
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

    private func analyticalRegions(for pose: Pose) -> [BodyRegion] {
        switch pose {
        case .front: return [.shoulders, .chest, .waist, .arms]
        case .side: return [.chest, .waist, .arms]
        case .back: return [.shoulders, .waist, .arms]
        case .frontDoubleBicep: return [.shoulders, .chest, .waist, .arms]
        case .sideChest: return [.chest, .waist, .arms]
        case .backDoubleBicep: return [.shoulders, .waist, .arms]
        case .mostMuscular: return [.shoulders, .chest, .waist, .arms]
        case .relaxedAesthetic: return [.chest, .waist, .arms]
        case .legs: return [.thighs]
        }
    }

    private func syntheticValue(for region: BodyRegion) -> Float {
        switch region {
        case .shoulders: return 0.50
        case .chest: return 0.42
        case .waist: return 0.30
        case .arms: return 0.12
        case .thighs: return 0.18
        }
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

    private func regional(
        _ region: BodyRegion,
        _ status: RegionalComparisonStatus,
        _ delta: Float?,
        pose: Pose = .front
    ) -> RegionalComparison {
        RegionalComparison(
            region: region,
            status: status,
            normalizedDelta: delta,
            contributions: [PoseContribution(
                pose: pose,
                baselineValue: status == .unavailable ? nil : 1,
                currentValue: status == .unavailable ? nil : 1 + (delta ?? 0),
                normalizedDelta: delta,
                poseMatchScore: status == .unavailable ? nil : 0.99,
                status: status == .unavailable ? .unavailable : .supported,
                reason: status == .unavailable ? "fixture_unavailable" : nil
            )],
            reason: status == .unavailable ? "fixture_unavailable" : nil
        )
    }

    private func pairComparison(
        relaxed: [RegionalComparison],
        optional: [PoseComparison] = []
    ) -> ScanPairComparison {
        ScanPairComparison(
            beforeScanID: UUID(),
            afterScanID: UUID(),
            availability: relaxed.contains { $0.status != .unavailable } || !optional.isEmpty
                ? .comparable
                : .partialEvidence,
            relaxedRegions: relaxed,
            poseComparisons: optional,
            evidenceStrength: .medium,
            reason: nil
        )
    }

    private func longitudinalObservation(
        _ status: RegionalComparisonStatus,
        index: Int
    ) -> LongitudinalVisualObservation {
        LongitudinalVisualObservation(
            afterScanID: UUID(),
            date: Date(timeIntervalSince1970: TimeInterval(index * 1_000)),
            status: status,
            normalizedDelta: status == .unavailable ? nil : (status == .stable ? 0 : (status == .increase ? 0.02 : -0.02)),
            reason: status == .unavailable ? "fixture_unavailable" : nil
        )
    }

    private func comparisonScan(
        id: UUID,
        date: Date,
        recipeID: UUID,
        pose: Pose
    ) -> Scan {
        Scan(
            id: id,
            date: date,
            captures: [PoseCapture(
                pose: pose,
                imageFilename: "\(id.uuidString).jpg",
                avgBrightness: 0.5,
                aspectRatio: 0.75,
                captureSource: .legacy
            )],
            consistencyScore: 0,
            lightingScore: 0,
            framingScore: 0,
            note: nil,
            analysisAvailability: .comparable,
            captureCompleteness: .complete,
            scanRole: .canonical,
            captureRecipeID: recipeID
        )
    }

    private func optionalAnalysis(scanID: UUID, pose: Pose, arms: Float) -> ScanAnalysis {
        var extractedPose = syntheticFixture(scale: 1, angleDegrees: 0, translation: (0, 0)).pose
        extractedPose.scanId = scanID
        extractedPose.pose = pose
        var result = analysis(profiles: [profile(
            pose: pose,
            values: [.shoulders: 0.50, .chest: 0.42, .waist: 0.30, .arms: arms],
            match: nil
        )])
        result.id = scanID
        result.analysisVersion = AnalysisStore.currentAnalysisVersion
        result.extractedPoses = [extractedPose]
        return result
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
