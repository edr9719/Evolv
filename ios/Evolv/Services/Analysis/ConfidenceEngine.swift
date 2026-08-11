import Foundation

/// Computes evidence strength from successful analysis evidence. Capture-review
/// assessments are intentionally not treated as analytical support.
enum ConfidenceEngine {

    // MARK: - Public API

    static func compute(
        scanCount: Int,
        qualityResult: QualityGateResult,
        assessments: [Pose: CaptureAssessment],
        analysisAvailability: AnalysisAvailability,
        poseMatchScore: Float?,
        measurementAgreementScore: Float,
        allAnalyses: [ScanAnalysis],
        goal: FitnessGoal,
        recompositionPatterns: [RecompositionPattern],
        regionalComparisons: [RegionalComparison]? = nil,
        thresholdsValidated: Bool = false,
        now: Date = Date()
    ) -> ConfidenceScore {
        // Evidence strength is descriptive, not a probability. Only successful
        // comparison-pipeline evidence contributes to the score.
        let scanComponent = min(1, max(0, Float(scanCount - 1) / 4)) * 0.20

        // 2. Pose match — how similar was the user's pose to their prior scan
        let poseMatch = poseMatchScore ?? 0
        let poseComponent = poseMatch * 0.30

        // 3. Lighting consistency — compare brightness with prior scan
        let lightingConsistency = computeLightingConsistency(
            current: qualityResult,
            prior: allAnalyses.sorted { $0.analyzedAt < $1.analyzedAt }.last?.qualityResult
        )
        let analyticalRegions = [BodyRegion.shoulders, .chest, .waist, .arms]
        let supportedRegions = Set((regionalComparisons ?? [])
            .filter { $0.status != .unavailable }
            .map(\.region))
        let supportedFraction: Float = regionalComparisons == nil
            ? 0
            : Float(supportedRegions.intersection(analyticalRegions).count) / Float(analyticalRegions.count)
        var rawScore = scanComponent + poseComponent + supportedFraction * 0.50

        let hasSufficientEvidence = analysisAvailability == .comparable
            && scanCount >= 2
            && poseMatchScore != nil
            && supportedFraction >= 0.5
            && thresholdsValidated

        if !hasSufficientEvidence || !thresholdsValidated {
            rawScore = min(rawScore, 0.35)
        }

        let overall: Confidence
        if !hasSufficientEvidence { overall = .low }
        else if rawScore >= 0.75 { overall = .high }
        else if rawScore >= 0.50 { overall = .medium }
        else { overall = .low }

        return ConfidenceScore(
            overall: overall,
            rawScore: rawScore,
            regionalCoverage: Dictionary(uniqueKeysWithValues: analyticalRegions.map {
                ($0.rawValue, supportedRegions.contains($0) ? Float(1) : Float(0))
            }),
            poseMatchScore: poseMatch,
            lightingConsistency: lightingConsistency,
            measurementAgreement: measurementAgreementScore,
            hasSufficientEvidence: hasSufficientEvidence
        )
    }

    // MARK: - Measurement Agreement Score

    /// Converts a dictionary of MeasurementAlignment values to a 0–1 score.
    static func measurementAgreementScore(from alignments: [String: MeasurementAlignment]) -> Float {
        guard !alignments.isEmpty else { return 0 }
        let scores: [Float] = alignments.values.map { alignment in
            switch alignment {
            case .agreementPositive, .agreementNegative: return 1.0
            case .measurementOnly, .visualOnly:          return 0.5
            case .noData:                                return 0
            case .conflictVisualUpMeasureDown,
                 .conflictVisualDownMeasureUp:           return 0.1
            }
        }
        return scores.reduce(0, +) / Float(scores.count)
    }

    // MARK: - Private

    private static func computeLightingConsistency(
        current: QualityGateResult,
        prior: QualityGateResult?
    ) -> Float {
        guard let prior else { return 0 }
        let diff = abs(current.brightnessScore - prior.brightnessScore)
        return max(0, 1.0 - diff * 3.0) // diff of 0.33 → 0.0
    }

    private static func computeRecency(analyses: [ScanAnalysis], now: Date) -> Float {
        guard let lastDate = analyses.sorted(by: { $0.analyzedAt < $1.analyzedAt }).last?.analyzedAt else {
            return 0
        }
        let daysSinceLast = now.timeIntervalSince(lastDate) / 86400
        if daysSinceLast <= 14 { return 1.0 }
        if daysSinceLast <= 30 { return 0.6 }
        return 0.2
    }
}
