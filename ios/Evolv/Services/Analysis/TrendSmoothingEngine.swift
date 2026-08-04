import Foundation

/// Applies EWMA smoothing with outlier suppression to per-region delta time series.
enum TrendSmoothingEngine {

    private static let alpha: Float = 0.3

    // MARK: - Public API

    static func smooth(
        allAnalyses: [ScanAnalysis],
        currentVisualSignals: VisualSignalSet
    ) -> SmoothedSignalSet {
        // Build time-ordered deltas per region from all prior analyses + current
        var regionSeries: [String: [Float]] = [:]

        for analysis in allAnalyses.sorted(by: { $0.analyzedAt < $1.analyzedAt }) {
            for delta in analysis.visualSignals.deltas {
                let key = delta.region.rawValue
                regionSeries[key, default: []].append(delta.normalizedDelta)
            }
        }
        // Append current values
        for delta in currentVisualSignals.deltas {
            let key = delta.region.rawValue
            regionSeries[key, default: []].append(delta.normalizedDelta)
        }

        var smoothedDeltas: [String: Float] = [:]
        for (key, series) in regionSeries {
            let cleaned = suppressOutliers(series)
            smoothedDeltas[key] = ewma(cleaned)
        }

        // Smooth taper and proportion ratio deltas from fat loss signals
        var taperSeries: [Float] = allAnalyses
            .sorted { $0.analyzedAt < $1.analyzedAt }
            .compactMap { $0.visualSignals.fatLossSignals?.taperIndexDelta }
        if let current = currentVisualSignals.fatLossSignals?.taperIndexDelta {
            taperSeries.append(current)
        }

        var propSeries: [Float] = allAnalyses
            .sorted { $0.analyzedAt < $1.analyzedAt }
            .compactMap { $0.visualSignals.fatLossSignals?.shoulderToWaistRatioDelta }
        if let current = currentVisualSignals.fatLossSignals?.shoulderToWaistRatioDelta {
            propSeries.append(current)
        }

        let smoothedTaper = ewma(suppressOutliers(taperSeries))
        let smoothedProp  = ewma(suppressOutliers(propSeries))
        let scanCount     = allAnalyses.count + 1

        return SmoothedSignalSet(
            smoothedDeltas: smoothedDeltas,
            smoothedTaperDelta: smoothedTaper,
            smoothedProportionDelta: smoothedProp,
            reliabilityTier: currentVisualSignals.reliabilityTier,
            scanCount: scanCount
        )
    }

    // MARK: - EWMA

    /// Exponential Weighted Moving Average with alpha = 0.3.
    /// Returns the final smoothed value, or last value if series is empty.
    static func ewma(_ series: [Float]) -> Float {
        guard !series.isEmpty else { return 0 }
        var s = series[0]
        for i in 1..<series.count {
            s = alpha * series[i] + (1 - alpha) * s
        }
        return s
    }

    // MARK: - Outlier Suppression

    /// Clamps values beyond 2σ from the mean to mean ± σ * 0.5.
    static func suppressOutliers(_ series: [Float]) -> [Float] {
        guard series.count > 2 else { return series }
        let mean = series.reduce(0, +) / Float(series.count)
        let variance = series.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(series.count)
        let sigma = sqrt(variance)
        let threshold = 2.0 * sigma
        return series.map { val in
            if abs(val - mean) > threshold {
                return mean + (val > mean ? 0.5 : -0.5) * sigma
            }
            return val
        }
    }
}
