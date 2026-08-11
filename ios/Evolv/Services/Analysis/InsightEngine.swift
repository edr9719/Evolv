import Foundation

/// Converts authoritative, on-device facts into restrained visual-shape wording.
/// Cloud output is optional prose only: it is rejected if it invents tissue claims
/// or contradicts the structured result.
enum InsightEngine {
    static func generateInsight(
        signals: InterpretedSignals,
        networkProxy: any InsightRequesting,
        allowCloud: Bool = false,
        now: Date = Date()
    ) async -> GeneratedInsight {
        guard signals.analysisAvailability == .comparable,
              !signals.signals.isEmpty,
              allowCloud else {
            return templateFallback(signals: signals, now: now)
        }

        if let insight = await requestWithRetry(signals: signals, proxy: networkProxy),
           InsightSafetyValidator.isSafe(insight, for: signals) {
            return insight
        }
        return templateFallback(signals: signals, now: now)
    }

    private static func requestWithRetry(
        signals: InterpretedSignals,
        proxy: any InsightRequesting
    ) async -> GeneratedInsight? {
        if let result = await proxy.requestInsight(signals: signals) { return result }
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return await proxy.requestInsight(signals: signals)
    }

    static func templateFallback(
        signals: InterpretedSignals,
        now: Date = Date()
    ) -> GeneratedInsight {
        GeneratedInsight(
            headline: buildHeadline(signals),
            detail: buildDetail(signals),
            caveat: buildCaveat(signals),
            regionNotes: buildRegionNotes(signals),
            momentum: buildMomentum(signals),
            confidence: signals.overallConfidence,
            generatedAt: now,
            source: .templateFallback
        )
    }

    private static func buildHeadline(_ signals: InterpretedSignals) -> String {
        switch signals.analysisAvailability {
        case .processingFailed:
            return "Photos saved — automatic analysis unavailable"
        case .partialEvidence:
            return "Not enough comparable evidence for a result"
        case .baselineOnly:
            return "Baseline saved — another comparable scan is required"
        case .documentationOnly:
            return "Photos saved — this extra scan is not used for comparison"
        case .validationOnly:
            return "Consistency-test set saved — excluded from progress"
        case .comparable, .none:
            break
        }

        guard !signals.signals.isEmpty else {
            return "Comparison saved — no supported regional result"
        }
        if signals.signals.values.allSatisfy({ $0 == .neutral }) {
            return "No meaningful visual change detected"
        }
        if signals.thresholdsValidated != true {
            return "Experimental visual difference detected"
        }
        return "Comparable visual differences detected"
    }

    private static func buildDetail(_ signals: InterpretedSignals) -> String {
        switch signals.analysisAvailability {
        case .processingFailed:
            return "Evolv could not process enough evidence to compare this scan. No region was guessed."
        case .partialEvidence:
            return "The required same-pose evidence was missing or conflicted, so Evolv did not produce a visual-change claim."
        case .baselineOnly:
            return "This scan establishes your visual reference. Progress cannot be assessed from one scan."
        case .documentationOnly:
            return "Same-day extra photos remain documentation-only and cannot alter the canonical comparison."
        case .validationOnly:
            return "This set belongs only to the local consistency test and cannot alter your progress timeline."
        case .comparable, .none:
            break
        }

        let descriptions = signals.signals
            .sorted { $0.key < $1.key }
            .compactMap { key, signal -> String? in
                guard let region = BodyRegion(rawValue: key) else { return nil }
                return factualSentence(region: region, signal: signal)
            }
        if descriptions.isEmpty {
            return "Only supported regions are reported. Unsupported regions were omitted."
        }
        return descriptions.joined(separator: " ")
    }

    private static func buildCaveat(_ signals: InterpretedSignals) -> String {
        var caveats: [String] = []
        if signals.thresholdsValidated != true, signals.analysisAvailability == .comparable {
            caveats.append("Non-neutral changes use provisional engineering thresholds and are experimental.")
        }
        if signals.overallConfidence == .low {
            caveats.append("Evidence strength is limited.")
        }
        if signals.unavailableRegions?.isEmpty == false {
            caveats.append("Unsupported regions were excluded rather than estimated.")
        }
        if signals.contextNotes.contains("possible_pump_state") {
            caveats.append("A pre-workout scan may change the visible outline temporarily.")
        }
        if signals.contextNotes.contains("possible_dehydration")
            || signals.contextNotes.contains("possible_water_retention") {
            caveats.append("Hydration differences may change the visible outline temporarily.")
        }
        caveats.append("Evolv compares visual silhouettes; it does not measure tissue or medical body composition.")
        return caveats.joined(separator: " ")
    }

    private static func buildMomentum(_ signals: InterpretedSignals) -> String {
        guard signals.analysisAvailability == .comparable else { return "Unavailable" }
        if signals.signals.values.allSatisfy({ $0 == .neutral }) { return "Stable" }
        return signals.thresholdsValidated == true ? "Changed" : "Experimental"
    }

    private static func buildRegionNotes(_ signals: InterpretedSignals) -> [String: String] {
        Dictionary(uniqueKeysWithValues: signals.signals.compactMap { key, signal in
            guard let region = BodyRegion(rawValue: key),
                  let sentence = factualSentence(region: region, signal: signal) else { return nil }
            return (key, sentence)
        })
    }

    private static func factualSentence(
        region: BodyRegion,
        signal: DirectionalSignal
    ) -> String? {
        switch signal {
        case .strongPositive, .moderatePositive, .minimalPositive:
            return "\(region.visualLabel) increased."
        case .neutral:
            return "\(region.visualLabel) remained stable."
        case .minimalNegative, .moderateNegative, .strongNegative:
            return "\(region.visualLabel) decreased."
        case .unclear:
            return nil
        }
    }
}

enum InsightSafetyValidator {
    private static let forbiddenClaims = [
        "fat loss", "lost fat", "muscle gain", "gained muscle",
        "muscle preserved", "body composition", "recomposition",
        "recomp", "lean mass", "body fat", "leaner", "more muscular",
        "less muscular", "toned", "progress detected", "progress made",
        "transformation detected"
    ]

    static func isSafe(_ insight: GeneratedInsight, for signals: InterpretedSignals) -> Bool {
        let fields = [insight.headline, insight.detail, insight.caveat, insight.momentum]
            + insight.regionNotes.flatMap { [$0.key, $0.value] }
        let text = fields.joined(separator: " ").lowercased()

        guard !forbiddenClaims.contains(where: text.contains) else { return false }

        for (key, signal) in signals.signals {
            guard let region = BodyRegion(rawValue: key) else { continue }
            let labels = [region.rawValue.lowercased(), region.visualLabel.lowercased()]
            let relevant = fields
                .flatMap { $0.lowercased().components(separatedBy: CharacterSet(charactersIn: ".!?;")) }
                .filter { sentence in labels.contains(where: sentence.contains) }
                .joined(separator: " ")
            guard !relevant.isEmpty else { continue }
            let increasedWords = ["increased", "increase", "wider", "larger", "grew", "growth"]
            let decreasedWords = ["decreased", "decrease", "narrower", "smaller", "reduced", "narrowing"]
            switch signal {
            case .strongPositive, .moderatePositive, .minimalPositive:
                if decreasedWords.contains(where: relevant.contains) { return false }
            case .minimalNegative, .moderateNegative, .strongNegative:
                if increasedWords.contains(where: relevant.contains) { return false }
            case .neutral:
                if increasedWords.contains(where: relevant.contains)
                    || decreasedWords.contains(where: relevant.contains) { return false }
            case .unclear:
                continue
            }
        }
        return true
    }
}
