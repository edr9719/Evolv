import Foundation

enum LoggedMeasurementMetric: String, CaseIterable, Identifiable, Hashable {
    case weight
    case arms
    case chest
    case waist
    case shoulders
    case thighs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weight: return "Weight"
        case .arms: return "Arm circumference"
        case .chest: return "Chest circumference"
        case .waist: return "Waist circumference"
        case .shoulders: return "Shoulder circumference"
        case .thighs: return "Thigh circumference"
        }
    }

    var bodyRegion: BodyRegion? {
        switch self {
        case .weight: return nil
        case .arms: return .arms
        case .chest: return .chest
        case .waist: return .waist
        case .shoulders: return .shoulders
        case .thighs: return .thighs
        }
    }

    var isMass: Bool { self == .weight }

    func value(in measurement: Measurement) -> Double? {
        switch self {
        case .weight: return measurement.weightKg
        case .arms: return measurement.arms
        case .chest: return measurement.chest
        case .waist: return measurement.waist
        case .shoulders: return measurement.shoulders
        case .thighs: return measurement.thighs
        }
    }
}

enum LoggedMeasurementComparisonStatus: String, Hashable {
    case stable
    case increase
    case decrease
    case unavailable
}

/// A direction-only relationship. It never upgrades visual evidence strength
/// and never treats circumference as the same quantity as a 2D silhouette.
enum MeasurementVisualRelationship: String, Hashable {
    case sameDirection
    case differentResult
    case visualUnavailable
}

struct LoggedMeasurementComparison: Identifiable, Hashable {
    var metric: LoggedMeasurementMetric
    var beforeValue: Double?
    var afterValue: Double?
    var delta: Double?
    var status: LoggedMeasurementComparisonStatus
    var visualRelationship: MeasurementVisualRelationship
    var unavailableReason: String?

    var id: String { metric.id }
}

/// Exact, user-entered measurements for one selected scan pair. Measurements
/// without an explicit scan link remain in historical charts but cannot be
/// silently assigned to either side of this comparison.
struct ScanPairMeasurementComparison: Hashable {
    var beforeScanID: UUID
    var afterScanID: UUID
    var beforeMeasurementID: UUID?
    var afterMeasurementID: UUID?
    var results: [LoggedMeasurementComparison]

    var supportedResults: [LoggedMeasurementComparison] {
        results.filter { $0.status != .unavailable }
    }

    var hasBothMeasurements: Bool {
        beforeMeasurementID != nil && afterMeasurementID != nil
    }
}

/// Analyzes historical measurement data to extract trend direction and alignment with visual signals.
enum MeasurementSignalEngine {

    // MARK: - Trend Direction

    enum TrendDirection {
        case up, down, stable
    }

    struct MeasurementTrend {
        var direction: TrendDirection
        var weeklySlope: Double  // kg or cm per week
        var dataPoints: Int
    }

    // MARK: - Public API

    static func measurement(for scanID: UUID, in measurements: [Measurement]) -> Measurement? {
        measurements
            .filter { $0.scanID == scanID }
            .max { $0.date < $1.date }
    }

    static func compare(
        beforeScanID: UUID,
        afterScanID: UUID,
        measurements: [Measurement],
        visualComparison: ScanPairComparison? = nil
    ) -> ScanPairMeasurementComparison {
        let before = measurement(for: beforeScanID, in: measurements)
        let after = measurement(for: afterScanID, in: measurements)
        let visual = visualComparison.flatMap {
            $0.beforeScanID == beforeScanID && $0.afterScanID == afterScanID ? $0 : nil
        }

        let results = LoggedMeasurementMetric.allCases.map { metric in
            compare(metric: metric, before: before, after: after, visualComparison: visual)
        }
        return ScanPairMeasurementComparison(
            beforeScanID: beforeScanID,
            afterScanID: afterScanID,
            beforeMeasurementID: before?.id,
            afterMeasurementID: after?.id,
            results: results
        )
    }

    static func weightTrend(from measurements: [Measurement]) -> MeasurementTrend? {
        let sorted = measurements
            .compactMap { measurement -> (Date, Double)? in
                guard let weight = measurement.weightKg else { return nil }
                return (measurement.date, weight)
            }
            .sorted { $0.0 < $1.0 }
        let recent = Array(sorted.suffix(8))
        guard recent.count >= 2 else { return nil }
        return linearTrend(dates: recent.map(\.0), values: recent.map(\.1))
    }

    private static func compare(
        metric: LoggedMeasurementMetric,
        before: Measurement?,
        after: Measurement?,
        visualComparison: ScanPairComparison?
    ) -> LoggedMeasurementComparison {
        let beforeValue = before.flatMap { metric.value(in: $0) }
        let afterValue = after.flatMap { metric.value(in: $0) }
        guard let beforeValue, let afterValue else {
            let reason: String
            if before == nil && after == nil {
                reason = "No measurements are linked to either scan."
            } else if before == nil {
                reason = "No measurement is linked to the before scan."
            } else if after == nil {
                reason = "No measurement is linked to the after scan."
            } else if beforeValue == nil && afterValue == nil {
                reason = "This value was not logged for either scan."
            } else if beforeValue == nil {
                reason = "This value was not logged for the before scan."
            } else {
                reason = "This value was not logged for the after scan."
            }
            return LoggedMeasurementComparison(
                metric: metric,
                beforeValue: beforeValue,
                afterValue: afterValue,
                delta: nil,
                status: .unavailable,
                visualRelationship: .visualUnavailable,
                unavailableReason: reason
            )
        }

        let delta = afterValue - beforeValue
        let status: LoggedMeasurementComparisonStatus
        if abs(delta) < 0.0001 {
            status = .stable
        } else {
            status = delta > 0 ? .increase : .decrease
        }
        return LoggedMeasurementComparison(
            metric: metric,
            beforeValue: beforeValue,
            afterValue: afterValue,
            delta: delta,
            status: status,
            visualRelationship: visualRelationship(
                measurementStatus: status,
                metric: metric,
                comparison: visualComparison
            ),
            unavailableReason: nil
        )
    }

    private static func visualRelationship(
        measurementStatus: LoggedMeasurementComparisonStatus,
        metric: LoggedMeasurementMetric,
        comparison: ScanPairComparison?
    ) -> MeasurementVisualRelationship {
        guard let comparison, let region = metric.bodyRegion else { return .visualUnavailable }
        let result: RegionalComparison?
        if region == .thighs {
            result = comparison.comparison(for: .legs)?.regions.first { $0.region == .thighs }
        } else {
            result = comparison.relaxedRegions.first { $0.region == region }
        }
        guard let result, result.status != .unavailable else { return .visualUnavailable }

        let same: Bool
        switch (measurementStatus, result.status) {
        case (.stable, .stable), (.increase, .increase), (.decrease, .decrease):
            same = true
        default:
            same = false
        }
        return same ? .sameDirection : .differentResult
    }

    static func bodyPartTrend(keyPath: KeyPath<Measurement, Double?>, from measurements: [Measurement]) -> MeasurementTrend? {
        let sorted = measurements.sorted { $0.date < $1.date }
        let valid = sorted.compactMap { m -> (Date, Double)? in
            guard let v = m[keyPath: keyPath] else { return nil }
            return (m.date, v)
        }
        let recent = Array(valid.suffix(6))
        guard recent.count >= 2 else { return nil }
        return linearTrend(dates: recent.map(\.0), values: recent.map(\.1))
    }

    /// Returns true if weight has been stable (|weekly slope| < 0.5 kg) over ≥ 4 measurements.
    static func isWeightStable(measurements: [Measurement]) -> Bool {
        guard let trend = weightTrend(from: measurements), trend.dataPoints >= 4 else { return false }
        return abs(trend.weeklySlope) < 0.5
    }

    // MARK: - Visual ↔ Measurement Alignment

    static func alignment(
        visualDelta: Float?,
        measurementTrend: MeasurementTrend?,
        region: BodyRegion
    ) -> MeasurementAlignment {
        guard let visual = visualDelta else {
            guard let m = measurementTrend else { return .noData }
            return m.direction == .stable ? .noData : .measurementOnly
        }
        guard let m = measurementTrend else { return .visualOnly }

        let visualUp   = visual > 0.008
        let visualDown = visual < -0.008

        switch m.direction {
        case .up:
            if visualUp   { return .agreementPositive }
            if visualDown { return .conflictVisualDownMeasureUp }
            return .measurementOnly
        case .down:
            if visualDown { return .agreementNegative }
            if visualUp   { return .conflictVisualUpMeasureDown }
            return .measurementOnly
        case .stable:
            if visualUp || visualDown { return .visualOnly }
            return .agreementNegative // both stable → no meaningful change
        }
    }

    // MARK: - Private

    private static func linearTrend(dates: [Date], values: [Double]) -> MeasurementTrend? {
        guard dates.count == values.count, dates.count >= 2 else { return nil }

        let t0 = dates[0].timeIntervalSinceReferenceDate
        let xs = dates.map { ($0.timeIntervalSinceReferenceDate - t0) / (7 * 86400) } // weeks
        let ys = values

        let n = Double(xs.count)
        let sumX  = xs.reduce(0, +)
        let sumY  = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map { $0 * $1 }.reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)

        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-9 else { return MeasurementTrend(direction: .stable, weeklySlope: 0, dataPoints: xs.count) }

        let slope = (n * sumXY - sumX * sumY) / denom

        let direction: TrendDirection
        if slope > 0.12 { direction = .up }
        else if slope < -0.12 { direction = .down }
        else { direction = .stable }

        return MeasurementTrend(direction: direction, weeklySlope: slope, dataPoints: xs.count)
    }
}
