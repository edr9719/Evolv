import Foundation

/// Generates human-readable physique insights.
/// Primary path: Supabase Edge Function → GPT-4o-mini.
/// Fallback path: deterministic template system (offline-safe).
enum InsightEngine {

    // MARK: - Public API

    static func generateInsight(
        signals: InterpretedSignals,
        networkProxy: NetworkProxy
    ) async -> GeneratedInsight {
        // Attempt LLM via proxy with one retry
        if let insight = await requestWithRetry(signals: signals, proxy: networkProxy) {
            return insight
        }
        return templateFallback(signals: signals)
    }

    // MARK: - LLM

    private static func requestWithRetry(
        signals: InterpretedSignals,
        proxy: NetworkProxy
    ) async -> GeneratedInsight? {
        if let result = await proxy.requestInsight(signals: signals) { return result }
        // Wait briefly then retry once
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return await proxy.requestInsight(signals: signals)
    }

    // MARK: - Template Fallback

    static func templateFallback(signals: InterpretedSignals) -> GeneratedInsight {
        let headline = buildHeadline(signals: signals)
        let detail   = buildDetail(signals: signals)
        let caveat   = buildCaveat(signals: signals)
        let momentum = buildMomentum(signals: signals)
        let regionNotes = buildRegionNotes(signals: signals)

        return GeneratedInsight(
            headline: headline,
            detail: detail,
            caveat: caveat,
            regionNotes: regionNotes,
            momentum: momentum,
            confidence: signals.overallConfidence,
            generatedAt: Date(),
            source: .templateFallback
        )
    }

    // MARK: - Headline Templates

    private static func buildHeadline(signals: InterpretedSignals) -> String {
        if signals.reliabilityTier == .noData || signals.reliabilityTier == .baseline {
            return "Baseline captured — keep scanning to reveal trends"
        }

        let patterns = signals.recompositionPatterns
        if patterns.contains(.silhouetteImprovementWeightStable) {
            return "Silhouette improving with stable weight — recomp in progress"
        }
        if patterns.contains(.waistNarrowingArmsStable) {
            return "Waist narrowing while muscle is preserved — solid fat loss signal"
        }
        if patterns.contains(.upperGrowthWaistStableOrDown) {
            return "Upper body growing without waist expansion — good muscle gain signal"
        }

        switch signals.goal {
        case .fatLoss:
            return headlineForFatLoss(signals: signals)
        case .muscleGain:
            return headlineForMuscleGain(signals: signals)
        case .recomp:
            return headlineForRecomp(signals: signals)
        case .maintain:
            return headlineForMaintain(signals: signals)
        }
    }

    private static func headlineForFatLoss(signals: InterpretedSignals) -> String {
        let waist = signals.signals[BodyRegion.waist.rawValue] ?? .unclear
        switch waist {
        case .strongNegative, .moderateNegative: return "Meaningful fat loss signal detected"
        case .minimalNegative: return "Early fat loss signal — stay the course"
        case .neutral: return "No visible change yet — body may be adapting"
        default: return "Mixed signals — consistency will clarify the trend"
        }
    }

    private static func headlineForMuscleGain(signals: InterpretedSignals) -> String {
        let arms      = signals.signals[BodyRegion.arms.rawValue]      ?? .unclear
        let shoulders = signals.signals[BodyRegion.shoulders.rawValue] ?? .unclear
        let chest     = signals.signals[BodyRegion.chest.rawValue]     ?? .unclear

        let positiveSignals: [DirectionalSignal] = [arms, shoulders, chest]
        let positiveCount = positiveSignals.filter { s -> Bool in
            s == .strongPositive || s == .moderatePositive || s == .minimalPositive
        }.count

        if positiveCount >= 2 { return "Multiple muscle groups showing visual growth" }
        if positiveCount == 1 { return "Early muscle gain signal in one region" }
        return "No significant visible growth yet — strength gains may still be happening"
    }

    private static func headlineForRecomp(signals: InterpretedSignals) -> String {
        if !signals.recompositionPatterns.isEmpty { return "Recomposition pattern detected" }
        return "Body composition shifting — recomp takes time to show visually"
    }

    private static func headlineForMaintain(signals: InterpretedSignals) -> String {
        let patterns = signals.recompositionPatterns
        if patterns.contains(.allRegionsStable) { return "Physique is stable — maintenance on track" }
        return "Minor variations detected — likely normal fluctuation"
    }

    // MARK: - Detail Templates

    private static func buildDetail(signals: InterpretedSignals) -> String {
        var parts: [String] = []

        if signals.reliabilityTier == .baseline || signals.reliabilityTier == .earlyStage {
            parts.append("With \(signals.scanCount) scan\(signals.scanCount == 1 ? "" : "s") logged, the system is still building a reliable baseline. Trends become clearer after 4+ consistent scans.")
            return parts.joined(separator: " ")
        }

        let taperSignal = signals.taperSignal
        if taperSignal == .strongPositive || taperSignal == .moderatePositive {
            parts.append("Your shoulder-to-waist ratio has improved, suggesting meaningful body composition change.")
        }

        if signals.recompositionPatterns.contains(.waistNarrowingArmsStable) {
            parts.append("Waist is narrowing while arm volume is being preserved — this is the fat loss signature you want to see.")
        }

        if signals.contextNotes.contains("possible_pump_state") {
            parts.append("Note: this scan was marked as post-workout — arm/chest measurements may reflect pump rather than baseline size.")
        }

        if signals.signalConflicts.contains("waist_signal_conflict") {
            parts.append("Visual and tape-measure waist signals disagree. This can happen when loose clothing or scan angle varies.")
        }

        if parts.isEmpty {
            return "The analysis engine is collecting data. Keep scanning on your regular schedule and signals will sharpen over time."
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Caveat Templates

    private static func buildCaveat(signals: InterpretedSignals) -> String {
        var caveats: [String] = []

        if signals.scanQualityNotes.contains("partial_body_coverage") {
            caveats.append("Partial body coverage may reduce accuracy for some regions.")
        }
        if signals.scanQualityNotes.contains("loose_clothing") {
            caveats.append("Loose clothing reduces the precision of silhouette analysis.")
        }
        if signals.overallConfidence == .low {
            caveats.append("Confidence is low — more scans on schedule will improve reliability.")
        }
        if signals.contextNotes.contains("possible_dehydration") {
            caveats.append("Low hydration can temporarily make you appear leaner than your actual baseline.")
        }
        if signals.contextNotes.contains("possible_water_retention") {
            caveats.append("High hydration may temporarily inflate visual measurements.")
        }

        return caveats.isEmpty
            ? "Results reflect visual silhouette analysis — not medical body composition measurement."
            : caveats.joined(separator: " ")
    }

    // MARK: - Momentum

    private static func buildMomentum(signals: InterpretedSignals) -> String {
        let positiveSignals = signals.signals.values.filter {
            $0 == .strongPositive || $0 == .moderatePositive
        }.count
        let negativeSignals = signals.signals.values.filter {
            $0 == .strongNegative || $0 == .moderateNegative
        }.count

        if !signals.recompositionPatterns.isEmpty { return "Building" }
        if positiveSignals >= 2 { return "Building" }
        if negativeSignals >= 2 { return "Declining" }
        return "Maintaining"
    }

    // MARK: - Region Notes

    private static func buildRegionNotes(signals: InterpretedSignals) -> [String: String] {
        var notes: [String: String] = [:]
        for (region, signal) in signals.signals {
            let note = regionNote(region: region, signal: signal, goal: signals.goal)
            if !note.isEmpty { notes[region] = note }
        }
        return notes
    }

    private static func regionNote(region: String, signal: DirectionalSignal, goal: FitnessGoal) -> String {
        switch signal {
        case .strongPositive:   return "Strong positive change detected."
        case .moderatePositive: return "Moderate positive trend."
        case .minimalPositive:  return "Slight positive trend — early signal."
        case .neutral:          return ""
        case .minimalNegative:  return "Slight decrease — within normal variation."
        case .moderateNegative: return "Moderate decrease detected."
        case .strongNegative:   return "Strong decrease — review your approach."
        case .unclear:          return "Insufficient data for this region."
        }
    }
}
