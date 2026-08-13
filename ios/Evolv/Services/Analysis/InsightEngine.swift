import Foundation

/// Produces the authoritative explanation for an exact user-selected pair.
/// It is deterministic and runs on-device. Generative prose may rephrase
/// separately persisted longitudinal facts, but it never replaces this result.
enum ComparisonNarrativeEngine {
    static func make(
        comparison: ScanPairComparison?,
        pose: Pose? = nil,
        goal: FitnessGoal,
        thresholds: AnalysisThresholdSet = .engineeringV1
    ) -> ComparisonNarrative {
        guard let comparison else {
            return unavailable(
                headline: "Analysis unavailable for this pair",
                detail: "Both scans need current on-device analysis before Evolv can describe their differences.",
                reason: nil,
                thresholds: thresholds
            )
        }

        if let reason = comparison.reason, reason != "no_supported_same_pose_evidence" {
            return unavailable(
                headline: reason == "capture_recipe_changed"
                    ? "These scans cannot be compared automatically"
                    : "Comparable evidence is unavailable",
                detail: explanation(for: reason),
                reason: reason,
                thresholds: thresholds
            )
        }

        let scoped = scopedResults(comparison: comparison, pose: pose)
        let supported = scoped.filter { $0.result.status != .unavailable }
        let unavailableCount = scoped.count - supported.count
        guard !supported.isEmpty else {
            let subject = pose.map { $0.category == .standard ? "the relaxed poses" : $0.label.lowercased() }
                ?? "this scan pair"
            return unavailable(
                headline: "No supported result for \(subject)",
                detail: "The required same-pose geometry or silhouette evidence was unavailable or conflicted. Evolv did not convert missing evidence into stability or change.",
                reason: comparison.reason,
                thresholds: thresholds
            )
        }

        let findings = supported.map { item in
            finding(
                result: item.result,
                pose: item.pose,
                evidenceStrength: item.pose.map { comparison.evidenceStrength(for: $0) }
                    ?? comparison.evidenceStrength,
                goal: goal
            )
        }
        let changed = findings.filter { $0.status == .increase || $0.status == .decrease }
        let stable = findings.filter { $0.status == .stable }
        let hasOptionalEvidence = scoped.contains { $0.pose?.category == .showcase }
        let status: ComparisonNarrativeStatus
        if !changed.isEmpty {
            status = .differenceDetected
        } else if unavailableCount > 0 {
            status = .limited
        } else {
            status = .stable
        }

        let headline = buildHeadline(
            status: status,
            pose: pose,
            changed: changed,
            thresholdsValidated: thresholds.isValidated
        )
        let detail = buildDetail(
            changed: changed,
            stable: stable,
            unavailableCount: unavailableCount,
            goal: goal
        )
        var limitations = [
            "Results describe normalized 2D silhouette evidence—not inches, muscle, fat, or body composition."
        ]
        if !thresholds.isValidated, !changed.isEmpty {
            limitations.append("Non-neutral differences use provisional engineering thresholds and remain experimental.")
        }
        if unavailableCount > 0 {
            limitations.append("\(unavailableCount) unsupported region\(unavailableCount == 1 ? " was" : "s were") excluded rather than estimated.")
        }
        if hasOptionalEvidence {
            limitations.append("Optional poses are compared only with the same pose and cannot change the relaxed-pose result.")
        }

        return ComparisonNarrative(
            status: status,
            headline: headline,
            detail: detail,
            findings: findings,
            limitations: limitations,
            evidenceStrength: pose.map { comparison.evidenceStrength(for: $0) }
                ?? comparison.evidenceStrength,
            thresholdSetIdentifier: thresholds.identifier,
            thresholdsValidated: thresholds.isValidated
        )
    }

    private struct ScopedResult {
        var pose: Pose?
        var result: RegionalComparison
    }

    private static func scopedResults(
        comparison: ScanPairComparison,
        pose: Pose?
    ) -> [ScopedResult] {
        if let pose {
            if pose.category == .standard {
                return comparison.relaxedRegions.map { ScopedResult(pose: nil, result: $0) }
            }
            return (comparison.comparison(for: pose)?.regions ?? []).map {
                ScopedResult(pose: pose, result: $0)
            }
        }

        let relaxed = comparison.relaxedRegions.map { ScopedResult(pose: nil, result: $0) }
        let optional = comparison.poseComparisons
            .filter { $0.pose.category == .showcase }
            .flatMap { poseComparison in
                poseComparison.regions.map { ScopedResult(pose: poseComparison.pose, result: $0) }
            }
        return relaxed + optional
    }

    private static func finding(
        result: RegionalComparison,
        pose: Pose?,
        evidenceStrength: Confidence,
        goal: FitnessGoal
    ) -> ComparisonNarrativeFinding {
        let label = result.region.visualLabel(for: pose)
        let posePrefix = pose.map { "\($0.label): " } ?? ""
        let statement: String
        switch result.status {
        case .stable:
            statement = "\(posePrefix)\(label) remained within Evolv's current stability band."
        case .increase, .decrease:
            let direction = result.status == .increase ? "increased" : "decreased"
            if let delta = result.normalizedDelta {
                statement = "\(posePrefix)\(label) \(direction) by \(formattedMagnitude(delta)) in the normalized 2D comparison."
            } else {
                statement = "\(posePrefix)\(label) \(direction) in the normalized 2D comparison."
            }
        case .unavailable:
            statement = ""
        }
        return ComparisonNarrativeFinding(
            pose: pose,
            region: result.region,
            status: result.status,
            normalizedDelta: result.normalizedDelta,
            evidenceStrength: evidenceStrength,
            goalAlignment: GoalAlignmentPolicy.alignment(
                status: result.status,
                region: result.region,
                goal: goal
            ),
            statement: statement
        )
    }

    private static func buildHeadline(
        status: ComparisonNarrativeStatus,
        pose: Pose?,
        changed: [ComparisonNarrativeFinding],
        thresholdsValidated: Bool
    ) -> String {
        switch status {
        case .stable:
            return "No meaningful visual change detected"
        case .limited:
            return "Supported regions remained stable"
        case .unavailable:
            return "Comparable evidence is unavailable"
        case .differenceDetected:
            let experimental = thresholdsValidated ? "" : "Experimental "
            if let pose, pose.category == .showcase {
                return "\(experimental)difference in \(pose.label.lowercased())"
            }
            if changed.allSatisfy({ $0.pose?.category == .showcase }) {
                return "\(experimental)optional-pose difference detected"
            }
            return "\(experimental)visual differences detected"
        }
    }

    private static func buildDetail(
        changed: [ComparisonNarrativeFinding],
        stable: [ComparisonNarrativeFinding],
        unavailableCount: Int,
        goal: FitnessGoal
    ) -> String {
        var sentences: [String] = []
        let orderedChanges = changed.sorted {
            abs($0.normalizedDelta ?? 0) > abs($1.normalizedDelta ?? 0)
        }
        sentences.append(contentsOf: orderedChanges.prefix(3).map(\.statement))
        if orderedChanges.count > 3 {
            sentences.append("\(orderedChanges.count - 3) additional supported difference\(orderedChanges.count - 3 == 1 ? " is" : "s are") listed below.")
        }
        if changed.isEmpty, !stable.isEmpty {
            let labels = stable.prefix(4).map { $0.region.visualLabel(for: $0.pose) }
            sentences.append("\(joined(labels)) remained within Evolv's current stability bands.")
        } else if !stable.isEmpty {
            sentences.append("\(stable.count) other supported region\(stable.count == 1 ? " remained" : "s remained") stable.")
        }

        let changedAlignment = changed.map(\.goalAlignment).filter { $0 != .notApplicable }
        if changedAlignment.contains(.favorable) && changedAlignment.contains(.unfavorable) {
            sentences.append("The supported directions are mixed relative to your \(goal.rawValue.lowercased()) goal.")
        } else if changedAlignment.contains(.favorable) {
            sentences.append("The supported direction is aligned with your \(goal.rawValue.lowercased()) goal, but it does not establish why the silhouette changed.")
        } else if changedAlignment.contains(.unfavorable) {
            sentences.append("The supported direction is not aligned with your \(goal.rawValue.lowercased()) goal, but it does not establish why the silhouette changed.")
        }
        if unavailableCount > 0 {
            sentences.append("Unsupported regions were left unavailable.")
        }
        return sentences.joined(separator: " ")
    }

    private static func unavailable(
        headline: String,
        detail: String,
        reason: String?,
        thresholds: AnalysisThresholdSet
    ) -> ComparisonNarrative {
        var limitations = [
            "No body-change claim was generated from unavailable evidence.",
            "Results describe normalized 2D silhouette evidence—not inches, muscle, fat, or body composition."
        ]
        if let reason { limitations.append("Reason code: \(reason).") }
        return ComparisonNarrative(
            status: .unavailable,
            headline: headline,
            detail: detail,
            findings: [],
            limitations: limitations,
            evidenceStrength: .low,
            thresholdSetIdentifier: thresholds.identifier,
            thresholdsValidated: thresholds.isValidated
        )
    }

    private static func explanation(for reason: String) -> String {
        switch reason {
        case "capture_recipe_changed":
            return "The scans used different camera setups, so apparent scale cannot be treated as body change. Both photos remain available for visual review."
        case "comparison_dates_not_chronological":
            return "Choose two different scans in chronological order."
        case "canonical_scans_required":
            return "Only canonical progress scans can produce an automatic progress comparison."
        case "current_analysis_unavailable":
            return "Both scans need current on-device analysis before Evolv can produce a result."
        default:
            return "The selected pair did not provide enough supported evidence. Evolv did not guess."
        }
    }

    private static func formattedMagnitude(_ value: Float) -> String {
        String(format: "%.1f%%", abs(value) * 100)
    }

    private static func joined(_ values: [String]) -> String {
        switch values.count {
        case 0: return "Supported regions"
        case 1: return values[0]
        case 2: return values.joined(separator: " and ")
        default: return values.dropLast().joined(separator: ", ") + ", and " + (values.last ?? "")
        }
    }
}

/// Goal context is intentionally computed after physical direction. Changing a
/// goal can change alignment wording, but never the measured direction.
enum GoalAlignmentPolicy {
    static func alignment(
        status: RegionalComparisonStatus,
        region: BodyRegion,
        goal: FitnessGoal
    ) -> GoalAlignment {
        guard status == .increase || status == .decrease else {
            return status == .stable ? .neutral : .notApplicable
        }
        let increased = status == .increase
        switch goal {
        case .maintain:
            return .unfavorable
        case .fatLoss:
            return region == .waist ? (increased ? .unfavorable : .favorable) : .notApplicable
        case .muscleGain:
            switch region {
            case .shoulders, .chest, .arms, .thighs:
                return increased ? .favorable : .unfavorable
            case .waist:
                return .notApplicable
            }
        case .recomp:
            switch region {
            case .waist:
                return increased ? .unfavorable : .favorable
            case .shoulders, .chest, .arms, .thighs:
                return increased ? .favorable : .unfavorable
            }
        }
    }
}

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
        "transformation detected", "inch", "centimeter", "millimeter", " cm", " mm"
    ]
    private static let increasedWords = ["increased", "increase", "wider", "larger", "grew", "growth"]
    private static let decreasedWords = ["decreased", "decrease", "narrower", "smaller", "reduced", "narrowing"]

    static func isSafe(_ insight: GeneratedInsight, for signals: InterpretedSignals) -> Bool {
        let fields = [insight.headline, insight.detail, insight.caveat, insight.momentum]
            + insight.regionNotes.flatMap { [$0.key, $0.value] }
        let text = fields.joined(separator: " ").lowercased()

        guard !forbiddenClaims.contains(where: text.contains) else { return false }
        guard confidenceRank(insight.confidence) <= confidenceRank(signals.overallConfidence) else {
            return false
        }

        // Region notes are an allowlist, not a place for cloud prose to add a
        // new analytical fact that the local engine never supplied.
        for (key, note) in insight.regionNotes {
            guard let region = BodyRegion(rawValue: key),
                  let signal = signals.signals[key],
                  sentence(note, agreesWith: signal, for: region) else {
                return false
            }
        }

        for (key, signal) in signals.signals {
            guard let region = BodyRegion(rawValue: key) else { continue }
            let labels = [region.rawValue.lowercased(), region.visualLabel.lowercased()]
            let relevant = fields
                .flatMap { $0.lowercased().components(separatedBy: CharacterSet(charactersIn: ".!?;")) }
                .filter { sentence in labels.contains(where: sentence.contains) }
                .joined(separator: " ")
            guard !relevant.isEmpty else { continue }
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

        // Unsupported and unavailable regions may be named as unavailable,
        // but they may not acquire a direction in generated prose.
        let supportedKeys = Set(signals.signals.keys)
        for region in BodyRegion.allCases where !supportedKeys.contains(region.rawValue) {
            let labels = [region.rawValue.lowercased(), region.visualLabel.lowercased()]
            let relevant = fields
                .flatMap { $0.lowercased().components(separatedBy: CharacterSet(charactersIn: ".!?;")) }
                .filter { sentence in labels.contains(where: sentence.contains) }
                .joined(separator: " ")
            if increasedWords.contains(where: relevant.contains)
                || decreasedWords.contains(where: relevant.contains) {
                return false
            }
        }

        if !signals.signals.isEmpty,
           signals.signals.values.allSatisfy({ $0 == .neutral }),
           insight.momentum.lowercased() != "stable" {
            return false
        }
        return true
    }

    private static func sentence(
        _ text: String,
        agreesWith signal: DirectionalSignal,
        for region: BodyRegion
    ) -> Bool {
        let lowered = text.lowercased()
        let labels = [region.rawValue.lowercased(), region.visualLabel.lowercased()]
        guard labels.contains(where: lowered.contains) else { return false }
        let saysIncrease = increasedWords.contains(where: lowered.contains)
        let saysDecrease = decreasedWords.contains(where: lowered.contains)
        switch signal {
        case .strongPositive, .moderatePositive, .minimalPositive:
            return saysIncrease && !saysDecrease
        case .neutral:
            return !saysIncrease && !saysDecrease
                && (lowered.contains("stable") || lowered.contains("unchanged"))
        case .minimalNegative, .moderateNegative, .strongNegative:
            return saysDecrease && !saysIncrease
        case .unclear:
            return false
        }
    }

    private static func confidenceRank(_ confidence: Confidence) -> Int {
        switch confidence {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
}
