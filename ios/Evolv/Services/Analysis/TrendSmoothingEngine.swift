import Foundation

/// Backward-compatible container builder for the current baseline-relative
/// signal. Earlier builds averaged baseline-relative deltas across weeks, which
/// could hide a real latest observation or turn scan count into apparent trend
/// support. Repetition is now evaluated explicitly by LongitudinalVisualEngine.
enum TrendSmoothingEngine {

    private static let alpha: Float = 0.3

    // MARK: - Public API

    static func smooth(
        allAnalyses: [ScanAnalysis],
        currentVisualSignals: VisualSignalSet
    ) -> SmoothedSignalSet {
        let currentDeltas = Dictionary(uniqueKeysWithValues: currentVisualSignals.deltas
            .filter { $0.region != .thighs }
            .map { ($0.region.rawValue, $0.normalizedDelta) })
        let currentTaper = currentVisualSignals.fatLossSignals?.taperIndexDelta ?? 0
        let currentProportion = currentVisualSignals.fatLossSignals?.shoulderToWaistRatioDelta ?? 0

        return SmoothedSignalSet(
            smoothedDeltas: currentDeltas,
            smoothedTaperDelta: currentTaper,
            smoothedProportionDelta: currentProportion,
            reliabilityTier: currentVisualSignals.reliabilityTier,
            scanCount: allAnalyses.count + 1
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

// MARK: - Truthful longitudinal patterns

enum LongitudinalPatternStatus: String, Hashable {
    case insufficientEvidence
    case repeatedStable
    case emergingIncrease
    case emergingDecrease
    case repeatedIncrease
    case repeatedDecrease
    case mixed

    var label: String {
        switch self {
        case .insufficientEvidence: return "Needs more evidence"
        case .repeatedStable: return "Repeated stable"
        case .emergingIncrease: return "One-scan increase"
        case .emergingDecrease: return "One-scan decrease"
        case .repeatedIncrease: return "Repeated increase"
        case .repeatedDecrease: return "Repeated decrease"
        case .mixed: return "Mixed results"
        }
    }
}

struct LongitudinalVisualObservation: Identifiable, Hashable {
    var afterScanID: UUID
    var date: Date
    var status: RegionalComparisonStatus
    var normalizedDelta: Float?
    var reason: String?

    var id: UUID { afterScanID }
}

struct LongitudinalVisualFinding: Identifiable, Hashable {
    /// Nil is the fused relaxed-pose result. Optional poses always remain
    /// isolated and can never confirm a relaxed-pose pattern.
    var pose: Pose?
    var region: BodyRegion
    var status: LongitudinalPatternStatus
    var observations: [LongitudinalVisualObservation]

    var id: String { "\(pose?.rawValue ?? "relaxed")-\(region.rawValue)" }
    var supportedObservationCount: Int {
        observations.filter { $0.status != .unavailable }.count
    }
    var latestDelta: Float? {
        observations.last.flatMap(\.normalizedDelta)
    }
}

struct LongitudinalVisualSummary: Hashable {
    var scanCount: Int
    var findings: [LongitudinalVisualFinding]
    var thresholdSetIdentifier: String
    var thresholdsValidated: Bool

    var relaxedFindings: [LongitudinalVisualFinding] {
        findings.filter { $0.pose == nil }
    }

    var optionalFindings: [LongitudinalVisualFinding] {
        findings.filter { $0.pose?.category == .showcase }
    }
}

struct LongitudinalPatternNarrative: Hashable {
    var headline: String
    var detail: String
    var caveat: String
}

/// Evaluates baseline-relative observations across time. A latest difference
/// is "repeated" only when the immediately preceding scan supports the same
/// direction. Missing evidence never gets skipped over to manufacture a run.
enum LongitudinalVisualEngine {
    static func evaluate(
        scans: [Scan],
        analyses: [UUID: ScanAnalysis],
        thresholds: AnalysisThresholdSet = .engineeringV1
    ) -> LongitudinalVisualSummary? {
        let chronological = scans
            .filter(\.isCanonicalProgressScan)
            .sorted { $0.date < $1.date }
        guard chronological.count >= 2 else { return nil }

        // The caller normally provides one active capture recipe. Keep the
        // engine fail-closed if a broader scan collection is supplied.
        let latestRecipe = chronological.last?.captureRecipeID
        let eligible = chronological.filter { $0.captureRecipeID == latestRecipe }
        guard eligible.count >= 2 else { return nil }

        var findings: [LongitudinalVisualFinding] = []
        if let relaxedAnchor = eligible.first {
            let pairs = eligible.dropFirst().map { after in
                (after, compare(anchor: relaxedAnchor, after: after, analyses: analyses, thresholds: thresholds))
            }
            for region in [BodyRegion.shoulders, .chest, .waist, .arms] {
                let observations = pairs.map { after, pair in
                    observation(
                        after: after,
                        result: pair.relaxedRegions.first { $0.region == region },
                        fallbackReason: pair.reason
                    )
                }
                findings.append(LongitudinalVisualFinding(
                    pose: nil,
                    region: region,
                    status: classify(observations),
                    observations: observations
                ))
            }
        }

        for pose in Pose.allCases where pose.category == .showcase {
            // A missing optional pose is not an interruption because the pose
            // was never attempted. Once the pose has a usable anchor, however,
            // every later attempt stays in the sequence. A failed extraction
            // therefore becomes unavailable instead of being skipped over to
            // manufacture a repeated pattern.
            let attemptedScans = eligible.filter { $0.capture(for: pose) != nil }
            guard let anchorIndex = attemptedScans.firstIndex(where: { scan in
                analyses[scan.id]?.silhouetteProfiles.contains { $0.pose == pose } == true
            }) else { continue }
            let anchoredScans = Array(attemptedScans[anchorIndex...])
            guard let anchor = anchoredScans.first, anchoredScans.count >= 2 else { continue }
            let pairs = anchoredScans.dropFirst().map { after in
                (after, compare(anchor: anchor, after: after, analyses: analyses, thresholds: thresholds))
            }
            for region in analyticalRegions(for: pose) {
                let observations = pairs.map { after, pair in
                    observation(
                        after: after,
                        result: pair.comparison(for: pose)?.regions.first { $0.region == region },
                        fallbackReason: pair.comparison(for: pose)?.reason ?? pair.reason
                    )
                }
                findings.append(LongitudinalVisualFinding(
                    pose: pose,
                    region: region,
                    status: classify(observations),
                    observations: observations
                ))
            }
        }

        return LongitudinalVisualSummary(
            scanCount: eligible.count,
            findings: findings,
            thresholdSetIdentifier: thresholds.identifier,
            thresholdsValidated: thresholds.isValidated
        )
    }

    static func narrative(for summary: LongitudinalVisualSummary?) -> LongitudinalPatternNarrative? {
        guard let summary else { return nil }
        let relaxed = summary.relaxedFindings
        let repeatedChanges = relaxed.filter {
            $0.status == .repeatedIncrease || $0.status == .repeatedDecrease
        }
        let emerging = relaxed.filter {
            $0.status == .emergingIncrease || $0.status == .emergingDecrease
        }
        let mixed = relaxed.filter { $0.status == .mixed }
        let stable = relaxed.filter { $0.status == .repeatedStable }

        let headline: String
        let detail: String
        if !mixed.isEmpty {
            headline = "Recent visual results are mixed"
            detail = statements(for: mixed).joined(separator: " ")
                + " Evolv is not calling this a consistent direction."
        } else if !repeatedChanges.isEmpty {
            headline = summary.thresholdsValidated
                ? "A visual pattern repeated"
                : "An experimental visual pattern repeated"
            detail = statements(for: repeatedChanges).joined(separator: " ")
        } else if !emerging.isEmpty {
            headline = "One scan shows a visual difference"
            detail = statements(for: emerging).joined(separator: " ")
                + " Another comparable scan is required before calling it repeated."
        } else if stable.count == relaxed.count, !stable.isEmpty {
            headline = "Repeated scans show visual stability"
            detail = "The supported relaxed regions stayed within Evolv's current stability bands in the two latest baseline comparisons."
        } else if !stable.isEmpty {
            headline = "Supported history is stable but incomplete"
            detail = "Some relaxed regions repeatedly stayed within their stability bands; the remaining regions do not have enough uninterrupted evidence."
        } else {
            headline = "More comparable scans are needed"
            detail = "Evolv does not yet have two uninterrupted supported observations for a longitudinal visual pattern."
        }

        let thresholdCaveat = summary.thresholdsValidated
            ? ""
            : " Change bands remain provisional and non-neutral patterns are experimental."
        return LongitudinalPatternNarrative(
            headline: headline,
            detail: detail,
            caveat: "This is repeated normalized 2D silhouette evidence—not inches, muscle, fat, or body composition.\(thresholdCaveat)"
        )
    }

    private static func compare(
        anchor: Scan,
        after: Scan,
        analyses: [UUID: ScanAnalysis],
        thresholds: AnalysisThresholdSet
    ) -> ScanPairComparison {
        ScanPairComparisonEngine.compare(
            before: anchor,
            after: after,
            beforeAnalysis: analyses[anchor.id],
            afterAnalysis: analyses[after.id],
            thresholds: thresholds
        )
    }

    private static func observation(
        after: Scan,
        result: RegionalComparison?,
        fallbackReason: String?
    ) -> LongitudinalVisualObservation {
        guard let result else {
            return LongitudinalVisualObservation(
                afterScanID: after.id,
                date: after.date,
                status: .unavailable,
                normalizedDelta: nil,
                reason: fallbackReason ?? "comparison_unavailable"
            )
        }
        return LongitudinalVisualObservation(
            afterScanID: after.id,
            date: after.date,
            status: result.status,
            normalizedDelta: result.normalizedDelta,
            reason: result.reason
        )
    }

    static func classify(_ observations: [LongitudinalVisualObservation]) -> LongitudinalPatternStatus {
        guard let latest = observations.last, latest.status != .unavailable else {
            return .insufficientEvidence
        }
        guard observations.count >= 2 else {
            switch latest.status {
            case .increase: return .emergingIncrease
            case .decrease: return .emergingDecrease
            case .stable, .unavailable: return .insufficientEvidence
            }
        }
        let previous = observations[observations.count - 2]
        guard previous.status != .unavailable else {
            switch latest.status {
            case .increase: return .emergingIncrease
            case .decrease: return .emergingDecrease
            case .stable, .unavailable: return .insufficientEvidence
            }
        }

        switch (previous.status, latest.status) {
        case (.stable, .stable):
            return .repeatedStable
        case (.increase, .increase):
            return .repeatedIncrease
        case (.decrease, .decrease):
            return .repeatedDecrease
        case (.increase, .decrease), (.decrease, .increase):
            return .mixed
        case (_, .increase):
            return .emergingIncrease
        case (_, .decrease):
            return .emergingDecrease
        case (.increase, .stable), (.decrease, .stable):
            return .mixed
        default:
            return .insufficientEvidence
        }
    }

    private static func analyticalRegions(for pose: Pose) -> [BodyRegion] {
        switch pose {
        case .frontDoubleBicep: return [.shoulders, .chest, .waist, .arms]
        case .sideChest: return [.chest, .waist, .arms]
        case .backDoubleBicep: return [.shoulders, .waist, .arms]
        case .mostMuscular: return [.shoulders, .chest, .waist, .arms]
        case .relaxedAesthetic: return [.chest, .waist, .arms]
        case .legs: return [.thighs]
        case .front, .side, .back: return []
        }
    }

    private static func statements(for findings: [LongitudinalVisualFinding]) -> [String] {
        findings.prefix(3).map { finding in
            let label = finding.region.visualLabel(for: finding.pose)
            switch finding.status {
            case .repeatedIncrease:
                return "\(label) increased from baseline in the two latest comparable scans."
            case .repeatedDecrease:
                return "\(label) decreased from baseline in the two latest comparable scans."
            case .emergingIncrease:
                return "\(label) increased from baseline in the latest comparable scan."
            case .emergingDecrease:
                return "\(label) decreased from baseline in the latest comparable scan."
            case .mixed:
                return "\(label) changed direction across recent scans."
            case .repeatedStable:
                return "\(label) repeatedly stayed within its stability band."
            case .insufficientEvidence:
                return ""
            }
        }.filter { !$0.isEmpty }
    }
}
