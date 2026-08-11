import Foundation

/// Translates smoothed visual deltas into literal physical-direction signals.
/// A user's goal is interpreted separately and can never reverse the sign of a result.
enum SignalInterpreter {

    // Delta thresholds for signal classification
    private static let strong:   Float = 0.04   // > 4%
    private static let moderate: Float = 0.02   // 2–4%
    private static let minimal:  Float = 0.005  // 0.5–2%

    // MARK: - Public API

    static func interpret(
        smoothed: SmoothedSignalSet,
        visualSignals: VisualSignalSet,
        measurements: [Measurement],
        profile: UserProfile,
        recompositionPatterns: [RecompositionPattern],
        qualityResult: QualityGateResult,
        assessments: [Pose: CaptureAssessment],
        analysisAvailability: AnalysisAvailability,
        allAnalyses: [ScanAnalysis],
        scanContext: ScanContext?,
        thresholds: AnalysisThresholdSet = .engineeringV1,
        now: Date = Date()
    ) -> InterpretedSignals {
        let goal = profile.goal
        let currentDeltas = Dictionary(uniqueKeysWithValues: visualSignals.deltas.map {
            ($0.region.rawValue, $0.normalizedDelta)
        })

        // Per-region signals
        var signals: [String: DirectionalSignal] = [:]
        for region in BodyRegion.allCases where region != .thighs {
            guard let delta = currentDeltas[region.rawValue] else { continue }
            signals[region.rawValue] = classify(delta: delta)
        }

        let taperSignal = visualSignals.fatLossSignals.map {
            classify(delta: $0.taperIndexDelta)
        } ?? .unclear
        let proportionSignal = visualSignals.fatLossSignals.map {
            classify(delta: $0.shoulderToWaistRatioDelta)
        } ?? .unclear

        // Measurement alignment per region
        var measurementAlignment: [String: MeasurementAlignment] = [:]
        measurementAlignment[BodyRegion.waist.rawValue] = waistAlignment(measurements: measurements, smoothed: smoothed)
        measurementAlignment["weight"] = weightAlignment(measurements: measurements, goal: goal)
        measurementAlignment[BodyRegion.arms.rawValue] = armsAlignment(measurements: measurements, smoothed: smoothed)
        measurementAlignment[BodyRegion.thighs.rawValue] = thighsAlignment(measurements: measurements)

        // Quality and conflict notes
        var qualityNotes: [String] = []
        if assessments.values.contains(where: { $0.status == .unavailable }) {
            qualityNotes.append("automatic_capture_check_unavailable")
        }
        if assessments.values.contains(where: { $0.userOverrodeRecommendation }) {
            qualityNotes.append("quality_recommendation_overridden")
        }
        if qualityResult.issues.contains(.tooDark) { qualityNotes.append("confirmed_extreme_darkness") }
        if qualityResult.issues.contains(.overexposed) { qualityNotes.append("confirmed_extreme_overexposure") }

        var conflicts: [String] = []
        for (region, alignment) in measurementAlignment {
            if alignment == .conflictVisualUpMeasureDown || alignment == .conflictVisualDownMeasureUp {
                conflicts.append("\(region)_signal_conflict")
            }
        }

        let contextNotes = buildContextNotes(scanContext)

        let weeksTracked: Int = {
            guard let first = allAnalyses.sorted(by: { $0.analyzedAt < $1.analyzedAt }).first?.analyzedAt else { return 0 }
            return Int(now.timeIntervalSince(first) / (7 * 86400))
        }()

        let overallConf: Confidence
        if !thresholds.isValidated || analysisAvailability != .comparable { overallConf = .low }
        else if smoothed.scanCount >= 8 && signals.count == 4 { overallConf = .high }
        else if smoothed.scanCount >= 4 && signals.count >= 2 { overallConf = .medium }
        else { overallConf = .low }

        var unavailableRegions: [String: String] = [:]
        for region in [BodyRegion.shoulders, .chest, .waist, .arms]
            where signals[region.rawValue] == nil {
            unavailableRegions[region.rawValue] = "insufficient_supported_comparison_evidence"
        }
        unavailableRegions[BodyRegion.thighs.rawValue] = "standard_scans_are_upper_body_only"

        let goalAlignments = Dictionary(uniqueKeysWithValues: signals.map { key, signal in
            let region = BodyRegion(rawValue: key)
            return (key, alignment(signal: signal, region: region, goal: goal))
        })

        return InterpretedSignals(
            scanCount: smoothed.scanCount,
            weeksTracked: weeksTracked,
            reliabilityTier: smoothed.reliabilityTier,
            goal: goal,
            overallConfidence: overallConf,
            signals: signals,
            taperSignal: taperSignal,
            proportionSignal: proportionSignal,
            measurementAlignment: measurementAlignment,
            recompositionPatterns: recompositionPatterns,
            scanQualityNotes: qualityNotes,
            signalConflicts: conflicts,
            contextNotes: contextNotes,
            unavailableRegions: unavailableRegions,
            analysisAvailability: analysisAvailability,
            goalAlignments: goalAlignments,
            signalSemanticsVersion: 2,
            thresholdSetIdentifier: thresholds.identifier,
            thresholdsValidated: thresholds.isValidated
        )
    }

    // MARK: - Signal Classification

    private static func classify(delta: Float) -> DirectionalSignal {
        let magnitude = abs(delta)
        let isPositive = delta > 0

        if magnitude >= strong {
            return isPositive ? .strongPositive : .strongNegative
        } else if magnitude >= moderate {
            return isPositive ? .moderatePositive : .moderateNegative
        } else if magnitude >= minimal {
            return isPositive ? .minimalPositive : .minimalNegative
        } else {
            return .neutral
        }
    }

    private static func alignment(
        signal: DirectionalSignal,
        region: BodyRegion?,
        goal: FitnessGoal
    ) -> GoalAlignment {
        guard let region, signal != .unclear else { return .notApplicable }
        if signal == .neutral { return .neutral }
        let increased = signal == .minimalPositive
            || signal == .moderatePositive
            || signal == .strongPositive

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

    // MARK: - Measurement Alignments

    private static func waistAlignment(measurements: [Measurement], smoothed: SmoothedSignalSet) -> MeasurementAlignment {
        let trend = MeasurementSignalEngine.bodyPartTrend(keyPath: \.waist, from: measurements)
        let visualDelta = smoothed.smoothedDeltas[BodyRegion.waist.rawValue]
        return MeasurementSignalEngine.alignment(visualDelta: visualDelta, measurementTrend: trend, region: .waist)
    }

    private static func armsAlignment(measurements: [Measurement], smoothed: SmoothedSignalSet) -> MeasurementAlignment {
        let trend = MeasurementSignalEngine.bodyPartTrend(keyPath: \.arms, from: measurements)
        let visualDelta = smoothed.smoothedDeltas[BodyRegion.arms.rawValue]
        return MeasurementSignalEngine.alignment(visualDelta: visualDelta, measurementTrend: trend, region: .arms)
    }

    private static func thighsAlignment(measurements: [Measurement]) -> MeasurementAlignment {
        let trend = MeasurementSignalEngine.bodyPartTrend(keyPath: \.thighs, from: measurements)
        guard let trend else { return .noData }
        return trend.direction == .stable ? .noData : .measurementOnly
    }

    private static func weightAlignment(measurements: [Measurement], goal: FitnessGoal) -> MeasurementAlignment {
        guard let trend = MeasurementSignalEngine.weightTrend(from: measurements) else { return .noData }
        switch goal {
        case .muscleGain:
            return trend.direction == .up ? .agreementPositive : .noData
        case .fatLoss:
            return trend.direction == .down ? .agreementPositive :
                   (trend.direction == .up ? .conflictVisualDownMeasureUp : .noData)
        case .recomp, .maintain:
            return trend.direction == .stable ? .agreementNegative : .visualOnly
        }
    }

    // MARK: - Context Notes

    static func buildContextNotes(_ context: ScanContext?) -> [String] {
        guard let ctx = context else { return [] }
        var notes: [String] = []
        if ctx.preWorkout == true  { notes.append("possible_pump_state") }
        if ctx.fasted == true      { notes.append("fasted_scan") }
        switch ctx.hydrationEstimate {
        case .low:    notes.append("possible_dehydration")
        case .high:   notes.append("possible_water_retention")
        default: break
        }
        switch ctx.timeOfDayCategory {
        case .morning: notes.append("morning_scan")
        case .night:   notes.append("late_night_scan")
        default: break
        }
        return notes
    }

}
