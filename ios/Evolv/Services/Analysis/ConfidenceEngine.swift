import Foundation

/// Computes an overall confidence score for a scan analysis.
enum ConfidenceEngine {

    // MARK: - Public API

    static func compute(
        scanCount: Int,
        qualityResult: QualityGateResult,
        poseMatchScore: Float?,
        measurementAgreementScore: Float,
        allAnalyses: [ScanAnalysis],
        goal: FitnessGoal,
        recompositionPatterns: [RecompositionPattern]
    ) -> ConfidenceScore {
        // 1. Scan count component — log-scaled 0–1 clamped at 10 scans
        let scanComponent = min(1.0, Float(log(Double(max(1, scanCount))) / log(10.0))) * 0.30

        // 2. Pose match — how similar was the user's pose to their prior scan
        let poseMatch = poseMatchScore ?? 0.5
        let poseComponent = poseMatch * 0.25

        // 3. Lighting consistency — compare brightness with prior scan
        let lightingConsistency = computeLightingConsistency(
            current: qualityResult,
            prior: allAnalyses.sorted { $0.analyzedAt < $1.analyzedAt }.last?.qualityResult
        )
        let lightingComponent = lightingConsistency * 0.20

        // 4. Measurement agreement — how well measurements corroborate visual signals
        // Goal-aware weighting: measurements matter less for recomp (both signals tell conflicting stories by design)
        let measurementWeight: Float = goal == .recomp ? 0.08 : 0.15
        let measurementComponent = measurementAgreementScore * measurementWeight
        let leftoverWeight: Float = 0.15 - measurementWeight

        // 5. Recency — reward recent scans (within 14 days)
        let recency = computeRecency(analyses: allAnalyses)
        let recencyComponent = recency * (0.10 + leftoverWeight)

        var rawScore = scanComponent + poseComponent + lightingComponent + measurementComponent + recencyComponent

        // Bonus for recomposition patterns detected
        if !recompositionPatterns.isEmpty {
            rawScore = min(1.0, rawScore + 0.10)
        }

        let overall: Confidence
        if rawScore >= 0.75 { overall = .high }
        else if rawScore >= 0.50 { overall = .medium }
        else { overall = .low }

        return ConfidenceScore(
            overall: overall,
            rawScore: rawScore,
            regionalCoverage: qualityResult.regionalCoverage,
            poseMatchScore: poseMatch,
            lightingConsistency: lightingConsistency,
            measurementAgreement: measurementAgreementScore
        )
    }

    // MARK: - Measurement Agreement Score

    /// Converts a dictionary of MeasurementAlignment values to a 0–1 score.
    static func measurementAgreementScore(from alignments: [String: MeasurementAlignment]) -> Float {
        guard !alignments.isEmpty else { return 0.5 } // neutral when no measurements
        let scores: [Float] = alignments.values.map { alignment in
            switch alignment {
            case .agreementPositive, .agreementNegative: return 1.0
            case .measurementOnly, .visualOnly:          return 0.7
            case .noData:                                return 0.5
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
        guard let prior else { return 0.7 } // no prior = give benefit of doubt
        let diff = abs(current.brightnessScore - prior.brightnessScore)
        return max(0, 1.0 - diff * 3.0) // diff of 0.33 → 0.0
    }

    private static func computeRecency(analyses: [ScanAnalysis]) -> Float {
        guard let lastDate = analyses.sorted(by: { $0.analyzedAt < $1.analyzedAt }).last?.analyzedAt else {
            return 0.5
        }
        let daysSinceLast = Date().timeIntervalSince(lastDate) / 86400
        if daysSinceLast <= 14 { return 1.0 }
        if daysSinceLast <= 30 { return 0.6 }
        return 0.2
    }
}
