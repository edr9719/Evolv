import SwiftUI
import Charts

struct StatsView: View {
    @Environment(AppState.self) private var app
    @State private var range: Range = .all

    enum Range: String, CaseIterable, Identifiable {
        case month = "1M"
        case quarter = "3M"
        case all = "All"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            NavigationStack {
                ZStack {
                    AmbientBackground()
                    ScrollView {
                        VStack(spacing: 20) {
                            rangePicker
                                .padding(.horizontal, 20)
                                .padding(.top, 4)
            
                            summaryStrip
                                .padding(.horizontal, 20)
            
                            weightCard
                                .padding(.horizontal, 20)
            
                            measurementsCard
                                .padding(.horizontal, 20)

                            if app.activeCanonicalScans.count >= 2 {
                                longitudinalPatternCard
                                    .padding(.horizontal, 20)
                            }
            
                            consistencyCard
                                .padding(.horizontal, 20)
            
                            progressRateCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 28)
                        }
                        .padding(.top, 8)
                    }
                    .scrollIndicators(.hidden)
                }
                .navigationTitle("Stats")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .trackView("StatsView")
    }

    // MARK: - Range picker

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(Range.allCases) { r in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { range = r }
                } label: {
                    Text(r.rawValue)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(range == r ? EvolvTheme.background : EvolvTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if range == r {
                                Capsule().fill(EvolvTheme.accent)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule().fill(EvolvTheme.surface).overlay(Capsule().stroke(EvolvTheme.stroke, lineWidth: 1))
        }
    }

    // MARK: - Filtered data

    private var filteredScans: [Scan] {
        let sorted = app.activeCanonicalScans
        guard let cutoff = cutoffDate else { return sorted }
        return sorted.filter { $0.date >= cutoff }
    }

    private var filteredMeasurements: [Measurement] {
        let sorted = app.measurements.sorted { $0.date < $1.date }
        guard let cutoff = cutoffDate else { return sorted }
        return sorted.filter { $0.date >= cutoff }
    }

    private var filteredWeightMeasurements: [Measurement] {
        filteredMeasurements.filter { $0.weightKg != nil }
    }

    private var cutoffDate: Date? {
        let cal = Calendar.current
        switch range {
        case .month:   return cal.date(byAdding: .month, value: -1, to: Date())
        case .quarter: return cal.date(byAdding: .month, value: -3, to: Date())
        case .all:     return nil
        }
    }

    // MARK: - Summary strip

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            statTile(value: "\(filteredScans.count)", label: "Scans")
            statTile(value: "\(app.currentStreak)", label: "Streak")
            statTile(value: weightChangeString, label: "Weight Δ", tint: weightChangeColor)
        }
    }

    private var weightChange: Double? {
        guard let first = filteredWeightMeasurements.first?.weightKg,
              let last = filteredWeightMeasurements.last?.weightKg,
              filteredWeightMeasurements.count >= 2 else { return nil }
        return last - first
    }

    private var weightChangeString: String {
        guard let weightChange else { return "—" }
        return UnitFormatter.signedMass(weightChange, unit: app.profile.massUnit)
    }

    private var weightChangeColor: Color {
        guard let v = weightChange else { return EvolvTheme.textMuted }
        switch app.profile.goal {
        case .muscleGain: return v > 0 ? EvolvTheme.improving : (v < 0 ? EvolvTheme.stalled : EvolvTheme.textMuted)
        case .fatLoss:    return v < 0 ? EvolvTheme.improving : (v > 0 ? EvolvTheme.stalled : EvolvTheme.textMuted)
        case .recomp, .maintain: return abs(v) < 1 ? EvolvTheme.improving : EvolvTheme.stable
        }
    }

    private func statTile(value: String, label: String, tint: Color = EvolvTheme.text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(EvolvTheme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(EvolvTheme.stroke, lineWidth: 1)
                }
        }
    }

    // MARK: - Weight card

    private var weightCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEIGHT")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(EvolvTheme.textFaint)
                        if let latest = filteredWeightMeasurements.last,
                           let weight = latest.weightKg {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", UnitFormatter.displayMassNumber(weight, unit: app.profile.massUnit)))
                                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                                    .foregroundStyle(EvolvTheme.text)
                                    .monospacedDigit()
                                Text(app.profile.massUnit.label)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(EvolvTheme.textFaint)
                            }
                        }
                    }
                    Spacer()
                    Text(weightChangeString)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(weightChangeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(weightChangeColor.opacity(0.14)))
                }

                if filteredWeightMeasurements.count >= 2 {
                    Chart(filteredWeightMeasurements) { m in
                        if let weight = m.weightKg {
                            LineMark(
                                x: .value("Date", m.date),
                                y: .value("Weight", weight)
                            )
                            .foregroundStyle(EvolvTheme.accent)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))

                            AreaMark(
                                x: .value("Date", m.date),
                                y: .value("Weight", weight)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [EvolvTheme.accent.opacity(0.28), EvolvTheme.accent.opacity(0)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.monotone)

                            PointMark(
                                x: .value("Date", m.date),
                                y: .value("Weight", weight)
                            )
                            .foregroundStyle(EvolvTheme.accent)
                            .symbolSize(36)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(EvolvTheme.stroke)
                            AxisValueLabel()
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(EvolvTheme.textFaint)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(EvolvTheme.textFaint)
                        }
                    }
                    .frame(height: 160)
                } else {
                    emptyChart("Log another weight to see your trend")
                        .frame(height: 100)
                }
            }
        }
    }

    // MARK: - Measurements card

    private var measurementsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("MEASUREMENT TRENDS")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(EvolvTheme.textFaint)

                VStack(spacing: 12) {
                    measurementRow("Arms", base: app.profile.arms, latest: filteredMeasurements.last?.arms, unit: "cm", goalUp: true)
                    Divider().overlay(EvolvTheme.stroke)
                    measurementRow("Chest", base: app.profile.chest, latest: filteredMeasurements.last?.chest, unit: "cm", goalUp: true)
                    Divider().overlay(EvolvTheme.stroke)
                    measurementRow("Waist", base: app.profile.waist, latest: filteredMeasurements.last?.waist, unit: "cm", goalUp: app.profile.goal == .muscleGain)
                    Divider().overlay(EvolvTheme.stroke)
                    measurementRow("Shoulders", base: app.profile.shoulders, latest: filteredMeasurements.last?.shoulders, unit: "cm", goalUp: true)
                    Divider().overlay(EvolvTheme.stroke)
                    measurementRow("Thighs", base: app.profile.thighs, latest: filteredMeasurements.last?.thighs, unit: "cm", goalUp: true)
                }
            }
        }
    }

    private func measurementRow(_ name: String, base: Double?, latest: Double?, unit: String, goalUp: Bool) -> some View {
        let lengthUnit = app.profile.lengthUnit
        let delta: Double? = {
            guard let b = base, let l = latest else { return nil }
            return l - b
        }()
        let status: TrendStatus = {
            guard let d = delta else { return .stable }
            if abs(d) < 0.3 { return .stable }
            if goalUp { return d > 0 ? .improving : .stalled }
            return d < 0 ? .improving : .stalled
        }()
        return HStack(spacing: 12) {
            Circle().fill(EvolvTheme.statusColor(status)).frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
            Spacer()
            if let latest {
                Text(UnitFormatter.displayLength(latest, unit: lengthUnit))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
            }
            if let d = delta {
                Text(UnitFormatter.signedLength(d, unit: lengthUnit))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.statusColor(status))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            } else {
                Text("—").font(.system(size: 12)).foregroundStyle(EvolvTheme.textFaint).frame(width: 70, alignment: .trailing)
            }
        }
    }

    // MARK: - Longitudinal visual patterns

    private var longitudinalPatternCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("LONGITUDINAL VISUAL PATTERNS")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(EvolvTheme.textFaint)
                    Spacer()
                    Text("Baseline referenced")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                }

                if let summary = app.longitudinalVisualSummary {
                    let narrative = LongitudinalVisualEngine.narrative(for: summary)
                    Text(narrative?.headline ?? "More comparable scans are needed")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text(narrative?.detail ?? "No repeated pattern is available.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(2)

                    Divider().overlay(EvolvTheme.stroke)
                    ForEach(summary.relaxedFindings) { finding in
                        longitudinalRow(finding)
                    }

                    let optional = summary.optionalFindings.filter { $0.supportedObservationCount > 0 }
                    if !optional.isEmpty {
                        Divider().overlay(EvolvTheme.stroke)
                        Text("OPTIONAL POSES · SAME POSE ONLY")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(EvolvTheme.textFaint)
                        ForEach(optional) { finding in
                            longitudinalRow(finding)
                        }
                    }

                    Text(narrative?.caveat ?? "Missing evidence is never treated as stability.")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                        .lineSpacing(2)
                } else {
                    emptyChart("Two current, comparable scans are required")
                        .frame(height: 90)
                }
            }
        }
    }

    private func longitudinalRow(_ finding: LongitudinalVisualFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(longitudinalColor(finding.status))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(finding.region.visualLabel(for: finding.pose))
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                if let pose = finding.pose {
                    Text(pose.label)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(finding.status.label)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(longitudinalColor(finding.status))
                Text("\(finding.supportedObservationCount) supported")
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func longitudinalColor(_ status: LongitudinalPatternStatus) -> Color {
        switch status {
        case .repeatedStable: return EvolvTheme.accent
        case .emergingIncrease, .emergingDecrease: return EvolvTheme.stable
        case .repeatedIncrease, .repeatedDecrease: return EvolvTheme.text
        case .mixed: return EvolvTheme.stalled
        case .insufficientEvidence: return EvolvTheme.textMuted
        }
    }

    // MARK: - Consistency card

    private var consistencyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("SCAN EVIDENCE")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(EvolvTheme.textFaint)
                    Spacer()
                    Text("\(filteredScans.count) scan\(filteredScans.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }

                if filteredScans.isEmpty {
                    emptyChart("Capture a scan to establish evidence").frame(height: 100)
                } else {
                    VStack(spacing: 10) {
                        ForEach(filteredScans.suffix(5)) { scan in
                            HStack {
                                Text(scan.date, format: .dateTime.day().month(.abbreviated))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(EvolvTheme.text)
                                Spacer()
                                Text(scan.analysisAvailability?.label ?? "Legacy")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(scan.analysisAvailability == .comparable ? EvolvTheme.accent : EvolvTheme.textMuted)
                            }
                        }
                    }
                }

                Text("A scan is comparable only where supported upper-body evidence overlaps with an earlier scan. Unsupported regions are left unavailable. Evolv does not turn image aspect ratio into a framing score.")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(2)
            }
        }
    }

    // MARK: - Progress rate card

    private var progressRateCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("LOGGED WEIGHT TREND")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(EvolvTheme.textFaint)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(rateLabel)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text(rateDescriptor)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                }
                Text("Calculated only from \(filteredWeightMeasurements.count) logged weights over \(weeksTracked) week\(weeksTracked == 1 ? "" : "s"). A weight trend alone does not establish muscle gain, fat loss, or visual progress.")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(2)
            }
        }
    }

    private var weeksTracked: Int {
        guard let first = filteredWeightMeasurements.first?.date,
              let last = filteredWeightMeasurements.last?.date else { return 0 }
        return max(0, Calendar.current.dateComponents([.weekOfYear], from: first, to: last).weekOfYear ?? 0)
    }

    private var rateLabel: String {
        guard filteredWeightMeasurements.count >= 2, weeksTracked > 0,
              let v = weightChange else { return "Not enough data" }
        let perWeek = v / Double(weeksTracked)
        let displayPerWeek = UnitFormatter.displayMassNumber(perWeek, unit: app.profile.massUnit)
        let sign = displayPerWeek > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", displayPerWeek)) \(app.profile.massUnit.label)/wk"
    }

    private var rateDescriptor: String {
        guard filteredWeightMeasurements.count >= 2, weeksTracked > 0,
              let weightChange else { return "Log over time" }
        let perWeek = weightChange / Double(weeksTracked)
        if abs(perWeek) < 0.05 { return "Stable scale weight" }
        return perWeek > 0 ? "Scale weight rising" : "Scale weight falling"
    }

    private func emptyChart(_ text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(EvolvTheme.textFaint)
                Text(text)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
            }
            Spacer()
        }
    }
}

#Preview { StatsView().environment(AppState()) }
