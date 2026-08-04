import Foundation

/// Translates smoothed signal data into goal-aware DirectionalSignals and assembles InterpretedSignals.
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
        allAnalyses: [ScanAnalysis],
        scanContext: ScanContext?
    ) -> InterpretedSignals {
        let goal = profile.goal

        // Per-region signals
        var signals: [String: DirectionalSignal] = [:]
        for region in BodyRegion.allCases {
            let delta = smoothed.smoothedDeltas[region.rawValue] ?? 0
            let coverage = qualityResult.regionalCoverage[regionCoverageKey(region)] ?? 0
            signals[region.rawValue] = classify(delta: delta, region: region, goal: goal, coverage: coverage)
        }

        let taperSignal      = classifyTaper(delta: smoothed.smoothedTaperDelta, goal: goal)
        let proportionSignal = classifyProportion(delta: smoothed.smoothedProportionDelta, goal: goal)

        // Measurement alignment per region
        var measurementAlignment: [String: MeasurementAlignment] = [:]
        measurementAlignment[BodyRegion.waist.rawValue] = waistAlignment(measurements: measurements, smoothed: smoothed)
        measurementAlignment["weight"] = weightAlignment(measurements: measurements, goal: goal)
        measurementAlignment[BodyRegion.arms.rawValue] = armsAlignment(measurements: measurements, smoothed: smoothed)

        // Quality and conflict notes
        var qualityNotes: [String] = []
        if qualityResult.coverageScore < 0.65 { qualityNotes.append("partial_body_coverage") }
        if qualityResult.issues.contains(.mirrorSelfieDetected) { qualityNotes.append("mirror_selfie") }
        if qualityResult.issues.contains(.looseClothingWarning) { qualityNotes.append("loose_clothing") }

        var conflicts: [String] = []
        for (region, alignment) in measurementAlignment {
            if alignment == .conflictVisualUpMeasureDown || alignment == .conflictVisualDownMeasureUp {
                conflicts.append("\(region)_signal_conflict")
            }
        }

        let contextNotes = buildContextNotes(scanContext)

        let weeksTracked: Int = {
            guard let first = allAnalyses.sorted(by: { $0.analyzedAt < $1.analyzedAt }).first?.analyzedAt else { return 0 }
            return Int(Date().timeIntervalSince(first) / (7 * 86400))
        }()

        let overallConf: Confidence
        if smoothed.scanCount >= 8 && qualityResult.coverageScore > 0.7 { overallConf = .high }
        else if smoothed.scanCount >= 4 { overallConf = .medium }
        else { overallConf = .low }

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
            contextNotes: contextNotes
        )
    }

    // MARK: - Signal Classification

    private static func classify(
        delta: Float,
        region: BodyRegion,
        goal: FitnessGoal,
        coverage: Float
    ) -> DirectionalSignal {
        if coverage < 0.5 { return .unclear }
        let positiveIsGood = positiveIsImprovement(region: region, goal: goal)
        return deltaToSignal(delta: delta, positiveIsGood: positiveIsGood)
    }

    private static func classifyTaper(delta: Float, goal: FitnessGoal) -> DirectionalSignal {
        return deltaToSignal(delta: delta, positiveIsGood: true)
    }

    private static func classifyProportion(delta: Float, goal: FitnessGoal) -> DirectionalSignal {
        return deltaToSignal(delta: delta, positiveIsGood: true)
    }

    private static func deltaToSignal(delta: Float, positiveIsGood: Bool) -> DirectionalSignal {
        let magnitude = abs(delta)
        let isPositive = delta > 0

        let rawTier: DirectionalSignal
        if magnitude >= strong {
            rawTier = isPositive ? .strongPositive : .strongNegative
        } else if magnitude >= moderate {
            rawTier = isPositive ? .moderatePositive : .moderateNegative
        } else if magnitude >= minimal {
            rawTier = isPositive ? .minimalPositive : .minimalNegative
        } else {
            return .neutral
        }

        if positiveIsGood { return rawTier }

        switch rawTier {
        case .strongPositive:   return .strongNegative
        case .moderatePositive: return .moderateNegative
        case .minimalPositive:  return .minimalNegative
        case .minimalNegative:  return .minimalPositive
        case .moderateNegative: return .moderatePositive
        case .strongNegative:   return .strongPositive
        default: return rawTier
        }
    }

    private static func positiveIsImprovement(region: BodyRegion, goal: FitnessGoal) -> Bool {
        switch goal {
        case .muscleGain:
            switch region {
            case .arms, .chest, .shoulders, .thighs: return true
            case .waist: return false
            }
        case .fatLoss:
            switch region {
            case .waist, .thighs: return false
            case .arms, .chest, .shoulders: return true
            }
        case .recomp:
            switch region {
            case .waist: return false
            case .arms, .chest, .shoulders, .thighs: return true
            }
        case .maintain:
            return false
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

    // MARK: - Helpers

    private static func regionCoverageKey(_ region: BodyRegion) -> String {
        switch region {
        case .shoulders:        return "shoulders"
        case .chest, .waist:    return "torso"
        case .arms:             return "arms"
        case .thighs:           return "thighs"
        }
    }
}
