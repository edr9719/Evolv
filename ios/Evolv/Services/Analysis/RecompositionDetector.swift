import Foundation

/// Identifies body recomposition patterns from smoothed signal sets and measurement data.
enum RecompositionDetector {

    // MARK: - Public API

    static func detect(
        smoothed: SmoothedSignalSet,
        measurements: [Measurement],
        goal: FitnessGoal
    ) -> [RecompositionPattern] {
        guard smoothed.scanCount >= 3 else { return [] }

        let deltas = smoothed.smoothedDeltas
        let waistDelta    = deltas[BodyRegion.waist.rawValue]     ?? 0
        let armsDelta     = deltas[BodyRegion.arms.rawValue]      ?? 0
        let shoulderDelta = deltas[BodyRegion.shoulders.rawValue] ?? 0
        let chestDelta    = deltas[BodyRegion.chest.rawValue]     ?? 0
        let taperDelta    = smoothed.smoothedTaperDelta
        let propDelta     = smoothed.smoothedProportionDelta

        let weightStable = MeasurementSignalEngine.isWeightStable(measurements: measurements)

        var patterns: [RecompositionPattern] = []

        // Pattern 1: waist narrowing + arms stable (classic fat loss with muscle preservation)
        if waistDelta < -0.015 && abs(armsDelta) < 0.008 {
            patterns.append(.waistNarrowingArmsStable)
        }

        // Pattern 2: silhouette improvement with stable weight (body recomp signature)
        if (taperDelta > 0.02 || propDelta > 0.02) && weightStable {
            patterns.append(.silhouetteImprovementWeightStable)
        }

        // Pattern 3: torso narrowing + upper body stable
        if waistDelta < -0.015 && shoulderDelta >= -0.005 && chestDelta >= -0.005 {
            patterns.append(.torsoNarrowingUpperBodyStable)
        }

        // Pattern 4: taper improvement with no overall size change
        if taperDelta > 0.02 && abs(shoulderDelta) < 0.01 && abs(waistDelta) < 0.01 {
            patterns.append(.taperImprovementNoSizeChange)
        }

        // Pattern 5: upper growth + waist stable or down (muscle gain with fat control)
        if (shoulderDelta > 0.015 || chestDelta > 0.015 || armsDelta > 0.015)
            && waistDelta <= 0.005 {
            patterns.append(.upperGrowthWaistStableOrDown)
        }

        // Pattern 6: all regions stable (maintenance)
        let allStable = [waistDelta, armsDelta, shoulderDelta, chestDelta].allSatisfy { abs($0) < 0.008 }
        if allStable && goal == .maintain {
            patterns.append(.allRegionsStable)
        }

        return patterns
    }
}
