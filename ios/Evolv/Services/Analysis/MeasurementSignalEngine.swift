import Foundation

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

    static func weightTrend(from measurements: [Measurement]) -> MeasurementTrend? {
        let sorted = measurements.sorted { $0.date < $1.date }
        let recent = Array(sorted.suffix(8))
        guard recent.count >= 2 else { return nil }
        return linearTrend(dates: recent.map(\.date), values: recent.map(\.weightKg))
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
