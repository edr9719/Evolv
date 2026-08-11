import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var showPaywall = false
    @State private var captureRequest: CaptureRequest? = nil
    @State private var showStartOptions = false
    @State private var detailRequest: ScanDetailRequest? = nil
    @State private var showStats = false
    @State private var showLogMeasurement = false
    @State private var showSettings = false

    var body: some View {
        Group {
            NavigationStack {
                ZStack {
                    AmbientBackground()
                    ScrollView {
                        VStack(spacing: 28) {
                            header
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
            
                            insightHero
                                .padding(.horizontal, 24)
            
                            if app.hasAnyScans {
                                summaryRow
                                    .padding(.horizontal, 24)
                            }
            
                            if !app.estimatedDeltas.isEmpty {
                                changesSection
                                    .padding(.horizontal, 24)
                            }
            
                            confidenceCard
                                .padding(.horizontal, 24)
            
                            actionRow
                                .padding(.horizontal, 24)
            
                            if app.hasAnyScans {
                                moreLink
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 28)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Image("evolv-logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 80)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showPaywall = true } label: {
                            Image(systemName: "sparkle")
                        }
                        .tint(EvolvTheme.accent)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 17, weight: .regular))
                        }
                        .tint(EvolvTheme.textMuted)
                    }
                }
                .sheet(isPresented: $showPaywall) { PaywallView() }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showStats) {
                    StatsView()
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showLogMeasurement) {
                    LogMeasurementSheet()
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
                .fullScreenCover(item: $captureRequest) { request in
                    CaptureFlowView(
                        scanRole: request.role,
                        repairScanID: request.repairScanID,
                        repairPoses: request.poses
                    )
                }
                .sheet(isPresented: $showStartOptions) {
                    if let today = app.todayCanonicalScan {
                        ScanStartOptionsSheet(
                            scanID: today.id,
                            onCapture: { captureRequest = $0 },
                            onView: { detailRequest = ScanDetailRequest(id: $0) }
                        )
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                    }
                }
                .sheet(item: $detailRequest) { request in
                    NavigationStack { ScanDetailView(scanID: request.id) }
                }
            }
        }
        .trackView("HomeView")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(EvolvTheme.textFaint)
            Text("Your progress, honestly.")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 5 ? "LATE NIGHT" : h < 12 ? "GOOD MORNING" : h < 17 ? "GOOD AFTERNOON" : "GOOD EVENING"
    }

    // MARK: - Hero insight

    private var insightHero: some View {
        let s = app.weeklySummary
        return GlassCard(padding: 26, cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(EvolvTheme.accent)
                    Text(app.hasAnyScans ? heroPeriodLabel : "WELCOME")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(EvolvTheme.textFaint)
                    Spacer()
                }

                Text(s.headline)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if !s.detail.isEmpty {
                    Text(s.detail)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    if app.latestAnalysis?.confidence.hasSufficientEvidence == true {
                        ConfidenceChip(confidence: s.confidence)
                    }
                    if let source = app.latestAnalysis?.generatedInsight?.source,
                       app.latestAnalysis?.analysisAvailability == .comparable {
                        Text(source.label)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(EvolvTheme.textFaint)
                    }
                    Spacer()
                    if let last = app.latestScan {
                        Text(last.date, format: .relative(presentation: .named))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(EvolvTheme.textFaint)
                    }
                }
            }
        }
    }

    private var heroPeriodLabel: String {
        let weeks = app.weeksTracked
        if weeks == 0 { return "THIS WEEK" }
        if weeks < 4 { return "WEEK \(weeks + 1)" }
        return "MONTH \(weeks / 4 + 1)"
    }

    private func trendIndicator(_ delta: Int) -> some View {
        let symbol = delta > 1 ? "arrow.up.right" : delta < -1 ? "arrow.down.right" : "arrow.right"
        let color: Color = delta > 1 ? EvolvTheme.improving : delta < -1 ? EvolvTheme.stalled : EvolvTheme.textMuted
        return Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .background(Circle().fill(color.opacity(0.12)))
    }

    // MARK: - Small summary row

    private var summaryRow: some View {
        return HStack(spacing: 10) {
            summaryCell(title: "Evidence", value: app.latestScan?.analysisAvailability?.label ?? "Legacy")
            summaryCell(title: "Progress scans", value: "\(app.canonicalScans.count)")
            summaryCell(title: "Measurements", value: "\(app.measurements.count)")
        }
    }

    private func summaryCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(EvolvTheme.textFaint)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(EvolvTheme.surface.opacity(0.7))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(EvolvTheme.stroke, lineWidth: 1)
                }
        }
    }

    // MARK: - Changes section

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ESTIMATED CHANGE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(EvolvTheme.textFaint)
                Spacer()
                Button { showLogMeasurement = true } label: {
                    Text("Update")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(app.estimatedDeltas.enumerated()), id: \.element.id) { idx, d in
                    MinimalDeltaRow(delta: d)
                    if idx < app.estimatedDeltas.count - 1 {
                        Divider().background(EvolvTheme.stroke).padding(.leading, 18)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(EvolvTheme.surface.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(EvolvTheme.stroke, lineWidth: 1)
                    }
            }
        }
    }

    // MARK: - Evidence card

    private var confidenceCard: some View {
        let (text, icon, color): (String, String, Color) = {
            if !app.hasAnyScans {
                return ("No scans yet — your first capture sets the baseline.", "camera", EvolvTheme.textMuted)
            }
            if app.analysisPending {
                return ("Analyzing only the regions supported by this scan.", "hourglass", EvolvTheme.textMuted)
            }
            if app.latestAnalysis?.analysisAvailability == .comparable,
               let confidence = app.latestAnalysis?.confidence,
               confidence.hasSufficientEvidence == true {
                return ("Latest analysis evidence: \(confidence.overall.label.lowercased())", "checkmark.seal.fill", EvolvTheme.improving)
            }
            if app.canonicalScans.count == 1 {
                return ("Baseline saved. A second comparable scan is required before progress can be assessed.", "viewfinder.circle", EvolvTheme.textMuted)
            }
            return ("Evidence is limited. Unsupported body regions were excluded instead of estimated.", "eye.slash", EvolvTheme.stable)
        }()

        return HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(Circle().fill(color.opacity(0.14)))
            Text(text)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .lineSpacing(2)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(EvolvTheme.surface.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(EvolvTheme.stroke, lineWidth: 1)
                }
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        VStack(spacing: 10) {
            EvolvPrimaryButton(
                title: captureButtonTitle,
                icon: "camera.fill"
            ) {
                beginCaptureDecision()
            }
            if app.hasAnyScans && app.measurements.count < 2 {
                Button { showLogMeasurement = true } label: {
                    Text("Log a measurement")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var captureButtonTitle: String {
        guard let today = app.todayCanonicalScan else {
            return app.hasAnyScans ? "New scan" : "Capture baseline"
        }
        return today.recommendedRepairPoses.isEmpty ? "Today's scan options" : "Improve today's scan"
    }

    private func beginCaptureDecision() {
        if app.todayCanonicalScan == nil {
            captureRequest = .newCanonical
        } else {
            showStartOptions = true
        }
    }

    // MARK: - More link

    private var moreLink: some View {
        Button { showStats = true } label: {
            HStack(spacing: 10) {
                Text("View detailed stats")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(EvolvTheme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Minimal delta row

struct MinimalDeltaRow: View {
    @Environment(AppState.self) private var app
    let delta: EstimatedDelta

    var body: some View {
        HStack(spacing: 14) {
            Text(delta.label)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
            Spacer()
            Text(displayValue)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var isMeaningful: Bool { abs(delta.value) >= 0.2 }

    private var displayValue: String {
        if !isMeaningful {
            if let note = delta.note { return note }
            return "Stable"
        }
        if delta.unit == "cm" {
            return UnitFormatter.signedLength(delta.value, unit: app.profile.lengthUnit)
        }
        let sign = delta.value > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f", delta.value)) \(delta.unit)"
    }

    private var valueColor: Color {
        if !isMeaningful { return EvolvTheme.textMuted }
        return EvolvTheme.statusColor(delta.status)
    }
}

// MARK: - Log measurement sheet

struct LogMeasurementSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var weightKg: Double = 76
    @State private var armsCm: Double = 36
    @State private var chestCm: Double = 100
    @State private var waistCm: Double = 80

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Log today's numbers")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Updates to Estimated Change. Skip any field you don't track.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        massField("Weight", kg: $weightKg, unit: app.profile.massUnit)
                        lengthField("Arms", cm: $armsCm, unit: app.profile.lengthUnit)
                        lengthField("Chest", cm: $chestCm, unit: app.profile.lengthUnit)
                        lengthField("Waist", cm: $waistCm, unit: app.profile.lengthUnit)

                        EvolvPrimaryButton(title: "Save measurement", icon: "checkmark") {
                            save()
                        }
                        .padding(.top, 8)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(EvolvTheme.textMuted)
                }
            }
            .onAppear {
                if let m = app.measurements.last {
                    weightKg = m.weightKg
                    armsCm = m.arms ?? app.profile.arms ?? 36
                    chestCm = m.chest ?? app.profile.chest ?? 100
                    waistCm = m.waist ?? app.profile.waist ?? 80
                } else {
                    weightKg = app.profile.weightKg
                    armsCm = app.profile.arms ?? 36
                    chestCm = app.profile.chest ?? 100
                    waistCm = app.profile.waist ?? 80
                }
            }
        }
    }

    private func massField(_ label: String, kg: Binding<Double>, unit: MassUnit) -> some View {
        let displayBinding = Binding<Double>(
            get: { UnitFormatter.displayMassNumber(kg.wrappedValue, unit: unit) },
            set: { kg.wrappedValue = UnitFormatter.toKg($0, unit: unit) }
        )
        return measurementField(
            label: label,
            unitLabel: unit.label,
            display: displayBinding,
            range: UnitFormatter.massRange(unit: unit),
            step: UnitFormatter.massStep(unit: unit),
            format: "%.1f"
        )
    }

    private func lengthField(_ label: String, cm: Binding<Double>, unit: LengthUnit) -> some View {
        let displayBinding = Binding<Double>(
            get: { UnitFormatter.displayLengthNumber(cm.wrappedValue, unit: unit) },
            set: { cm.wrappedValue = UnitFormatter.toCm($0, unit: unit) }
        )
        return measurementField(
            label: label,
            unitLabel: unit.label,
            display: displayBinding,
            range: UnitFormatter.bodyPartRange(unit: unit),
            step: UnitFormatter.bodyPartStep(unit: unit),
            format: unit == .cm ? "%.1f" : "%.2f"
        )
    }

    private func measurementField(label: String, unitLabel: String, display: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                Spacer()
                HStack(spacing: 4) {
                    Text(String(format: format, display.wrappedValue))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                        .monospacedDigit()
                    Text(unitLabel)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                }
            }
            Slider(value: display, in: range, step: step).tint(EvolvTheme.accent)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(EvolvTheme.stroke, lineWidth: 1) }
        }
    }

    private func save() {
        let m = Measurement(date: Date(), weightKg: weightKg, arms: armsCm, chest: chestCm, waist: waistCm, shoulders: app.profile.shoulders, thighs: app.profile.thighs)
        app.addMeasurement(m)
        dismiss()
    }
}

#Preview {
    HomeView().environment(AppState())
}
