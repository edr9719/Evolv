import XCTest
@testable import Evolv

final class AnalysisTruthfulnessTests: XCTestCase {

    func testStandardProfilesNeverProduceThighVisualSignal() {
        let baseline = profile(thigh: 0.10)
        let current = profile(thigh: 0.30)
        let history = (0..<3).map { index in analysis(id: UUID(), profile: baseline, day: index) }

        let result = VisualSignalEngine.compute(
            currentProfiles: [current],
            allScanAnalyses: history
        )

        XCTAssertFalse(result.deltas.contains { $0.region == .thighs })
    }

    func testBaselineHasNoFabricatedVisualDeltas() {
        let result = VisualSignalEngine.compute(
            currentProfiles: [profile(thigh: 0.25)],
            allScanAnalyses: []
        )

        XCTAssertEqual(result.reliabilityTier, .baseline)
        XCTAssertTrue(result.deltas.isEmpty)
    }

    func testMissingEvidenceCannotProducePositiveConfidence() {
        let quality = QualityGateEngine.qualityResult(
            from: QualityGateEngine.unavailableAssessment(reason: "test")
        )

        let confidence = ConfidenceEngine.compute(
            scanCount: 1,
            qualityResult: quality,
            assessments: [:],
            analysisAvailability: .baselineOnly,
            poseMatchScore: nil,
            measurementAgreementScore: 0,
            allAnalyses: [],
            goal: .muscleGain,
            recompositionPatterns: []
        )

        XCTAssertEqual(confidence.overall, .low)
        XCTAssertEqual(confidence.hasSufficientEvidence, false)
        XCTAssertLessThanOrEqual(confidence.rawScore, 0.35)
    }

    func testPartialEvidenceInsightMakesNoProgressClaim() {
        let signals = InterpretedSignals(
            scanCount: 2,
            weeksTracked: 1,
            reliabilityTier: .earlyStage,
            goal: .muscleGain,
            overallConfidence: .low,
            signals: [:],
            taperSignal: .unclear,
            proportionSignal: .unclear,
            measurementAlignment: [:],
            recompositionPatterns: [],
            scanQualityNotes: ["automatic_capture_check_unavailable"],
            signalConflicts: [],
            contextNotes: [],
            unavailableRegions: ["arms": "insufficient_supported_comparison_evidence"],
            analysisAvailability: .partialEvidence
        )

        let insight = InsightEngine.templateFallback(signals: signals)

        XCTAssertEqual(insight.headline, "Not enough comparable evidence for a result")
        XCTAssertTrue(insight.detail.contains("did not produce a visual-change claim"))
    }

    private func profile(thigh: Float) -> SilhouetteProfile {
        SilhouetteProfile(
            scanId: UUID(),
            pose: .front,
            widthAtY: Array(repeating: 0.2, count: 100),
            shoulderWidthRatio: 0.35,
            chestWidthRatio: 0.30,
            waistWidthRatio: 0.25,
            armMidWidthRatio: 0.28,
            thighMidWidthRatio: thigh,
            taperIndex: 0.28,
            chestToWaistRatio: 1.2,
            shoulderToWaistRatio: 1.4,
            hipWidthRatio: nil,
            lowerTorsoWidthRatio: 0.25,
            supportedRegions: [.shoulders, .chest, .waist, .arms]
        )
    }

    private func analysis(id: UUID, profile: SilhouetteProfile, day: Int) -> ScanAnalysis {
        let quality = QualityGateResult(
            verdict: .pass,
            issues: [],
            blurScore: 0,
            brightnessScore: 0.5,
            coverageScore: 1,
            regionalCoverage: ["shoulders": 1, "torso": 1, "arms": 1]
        )
        let visual = VisualSignalSet(deltas: [], fatLossSignals: nil, reliabilityTier: .baseline)
        let smoothed = SmoothedSignalSet(
            smoothedDeltas: [:],
            smoothedTaperDelta: 0,
            smoothedProportionDelta: 0,
            reliabilityTier: .baseline,
            scanCount: 1
        )
        let confidence = ConfidenceScore(
            overall: .low,
            rawScore: 0,
            regionalCoverage: [:],
            poseMatchScore: 0,
            lightingConsistency: 0,
            measurementAgreement: 0,
            hasSufficientEvidence: false
        )
        let interpreted = InterpretedSignals(
            scanCount: 1,
            weeksTracked: 0,
            reliabilityTier: .baseline,
            goal: .muscleGain,
            overallConfidence: .low,
            signals: [:],
            taperSignal: .unclear,
            proportionSignal: .unclear,
            measurementAlignment: [:],
            recompositionPatterns: [],
            scanQualityNotes: [],
            signalConflicts: [],
            contextNotes: [],
            unavailableRegions: nil,
            analysisAvailability: .baselineOnly
        )
        return ScanAnalysis(
            id: id,
            analysisVersion: 2,
            analyzedAt: Date(timeIntervalSinceReferenceDate: Double(day * 86_400)),
            qualityResult: quality,
            extractedPoses: [],
            silhouetteProfiles: [profile],
            visualSignals: visual,
            smoothedSignals: smoothed,
            confidence: confidence,
            interpretedSignals: interpreted,
            generatedInsight: nil,
            captureAssessments: nil,
            analysisAvailability: .baselineOnly,
            poseFailures: nil
        )
    }
}
