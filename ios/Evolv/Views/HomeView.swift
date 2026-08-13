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
            
                            if !app.activeCanonicalScans.isEmpty {
                                summaryRow
                                    .padding(.horizontal, 24)
                            }
            
                            if let measurementComparison = app.currentMeasurementComparison,
                               !measurementComparison.supportedResults.isEmpty {
                                changesSection(measurementComparison)
                                    .padding(.horizontal, 24)
                            }
            
                            confidenceCard
                                .padding(.horizontal, 24)
            
                            actionRow
                                .padding(.horizontal, 24)
            
                            if !app.activeCanonicalScans.isEmpty {
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
                    LogMeasurementSheet(
                        scanID: app.activeLatestScan?.id,
                        measurementDate: app.activeLatestScan?.date
                    )
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
                    Text(app.activeCanonicalScans.isEmpty ? "WELCOME" : heroPeriodLabel)
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
                    if let narrative = app.currentProgressNarrative,
                       narrative.status != .unavailable,
                       !narrative.findings.isEmpty {
                        ConfidenceChip(confidence: s.confidence)
                        Text("On-device evidence summary")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(EvolvTheme.textFaint)
                    } else if let source = app.latestAnalysis?.generatedInsight?.source,
                       app.latestAnalysis?.analysisAvailability == .comparable {
                        Text(source.label)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(EvolvTheme.textFaint)
                    }
                    Spacer()
                    if let last = app.activeLatestScan {
                        Text(last.date, format: .relative(presentation: .named))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(EvolvTheme.textFaint)
                    }
                }
            }
        }
    }

    private var heroPeriodLabel: String {
        if app.activeCanonicalScans.count >= 2 { return "SINCE CURRENT BASELINE" }
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
            summaryCell(title: "Evidence", value: app.activeLatestScan?.analysisAvailability?.label ?? "Legacy")
            summaryCell(title: "Progress scans", value: "\(app.activeCanonicalScans.count)")
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

    private func changesSection(_ comparison: ScanPairMeasurementComparison) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BASELINE → LATEST MEASUREMENTS")
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
                ForEach(Array(comparison.supportedResults.enumerated()), id: \.element.id) { idx, result in
                    LoggedMeasurementDeltaRow(result: result)
                    if idx < comparison.supportedResults.count - 1 {
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
            Text("Exact values you entered for these two scans. Photo-based findings remain separate.")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(EvolvTheme.textFaint)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Evidence card

    private var confidenceCard: some View {
        let (text, icon, color): (String, String, Color) = {
            if app.activeCanonicalScans.isEmpty {
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
            if app.activeCanonicalScans.count == 1 {
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
            if let latest = app.activeLatestScan, app.measurement(for: latest.id) == nil {
                Button { showLogMeasurement = true } label: {
                    Text("Add measurements to latest scan")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var captureButtonTitle: String {
        guard let today = app.todayCanonicalScan else {
            return app.activeCanonicalScans.isEmpty ? "Capture baseline" : "New scan"
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

// MARK: - Logged measurement delta

struct LoggedMeasurementDeltaRow: View {
    @Environment(AppState.self) private var app
    let result: LoggedMeasurementComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 14) {
                Text(result.metric.label)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Spacer()
                Text(displayValue)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
            }
            if let relationshipText {
                Text(relationshipText)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(relationshipColor)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }

    private var displayValue: String {
        guard let delta = result.delta else { return "Not logged" }
        if result.status == .stable { return "No logged change" }
        if result.metric.isMass {
            return UnitFormatter.signedMass(delta, unit: app.profile.massUnit)
        }
        return UnitFormatter.signedLength(
            delta,
            unit: app.profile.lengthUnit,
            fractionDigits: app.profile.lengthUnit == .cm ? 1 : 2
        )
    }

    private var valueColor: Color {
        result.status == .stable ? EvolvTheme.accent : EvolvTheme.text
    }

    private var relationshipText: String? {
        switch result.visualRelationship {
        case .sameDirection: return "Same direction as the photo silhouette"
        case .differentResult: return "Different result from the photo silhouette"
        case .visualUnavailable: return nil
        }
    }

    private var relationshipColor: Color {
        result.visualRelationship == .differentResult ? EvolvTheme.stable : EvolvTheme.textFaint
    }
}

// MARK: - Log measurement sheet

struct LogMeasurementSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let scanID: UUID?
    let measurementDate: Date?

    @State private var includeWeight = false
    @State private var includeArms = false
    @State private var includeChest = false
    @State private var includeWaist = false
    @State private var includeShoulders = false
    @State private var includeThighs = false
    @State private var weightKg: Double = 76
    @State private var armsCm: Double = 36
    @State private var chestCm: Double = 100
    @State private var waistCm: Double = 80
    @State private var shouldersCm: Double = 110
    @State private var thighsCm: Double = 55
    @State private var didInitialize = false
    @State private var saveError: String? = nil
    @State private var confirmDelete = false

    init(scanID: UUID? = nil, measurementDate: Date? = nil) {
        self.scanID = scanID
        self.measurementDate = measurementDate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        Text(existingMeasurement == nil ? "Log measured values" : "Edit measured values")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(introText)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        optionalMassField("Weight", included: $includeWeight, kg: $weightKg)
                        optionalLengthField("Arm circumference", included: $includeArms, cm: $armsCm)
                        optionalLengthField("Chest circumference", included: $includeChest, cm: $chestCm)
                        optionalLengthField("Waist circumference", included: $includeWaist, cm: $waistCm)
                        optionalLengthField("Shoulder circumference", included: $includeShoulders, cm: $shouldersCm)
                        optionalLengthField("Thigh circumference", included: $includeThighs, cm: $thighsCm)

                        EvolvPrimaryButton(title: "Save measurement", icon: "checkmark") {
                            save()
                        }
                        .disabled(!hasAnyIncludedValue)
                        .opacity(hasAnyIncludedValue ? 1 : 0.45)
                        .padding(.top, 8)

                        if existingMeasurement != nil {
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Text("Remove measurement from this scan")
                                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(EvolvTheme.stalled)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(scanID == nil ? "Measurement" : "Scan measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(EvolvTheme.textMuted)
                }
            }
            .onAppear {
                initializeOnce()
            }
            .alert("Measurement wasn't saved", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "Please try again.")
            }
            .confirmationDialog(
                "Remove this measurement?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Remove measurement", role: .destructive) {
                    deleteExistingMeasurement()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The scan and its photos will stay saved. Only the linked weight and tape values will be removed.")
            }
        }
    }

    private var existingMeasurement: Measurement? {
        scanID.flatMap { app.measurement(for: $0) }
    }

    private var introText: String {
        let scope = scanID == nil
            ? "This entry stays in your measurement history."
            : "These values will be linked only to this scan for exact before-and-after comparisons."
        return "\(scope) Turn on only values you actually measured. Tape and weight results stay separate from photo-based silhouette evidence."
    }

    private var hasAnyIncludedValue: Bool {
        includeWeight || includeArms || includeChest || includeWaist || includeShoulders || includeThighs
    }

    private func optionalMassField(
        _ label: String,
        included: Binding<Bool>,
        kg: Binding<Double>
    ) -> some View {
        optionalField(label, included: included) {
            massField(label, kg: kg, unit: app.profile.massUnit)
        }
    }

    private func optionalLengthField(
        _ label: String,
        included: Binding<Bool>,
        cm: Binding<Double>
    ) -> some View {
        optionalField(label, included: included) {
            lengthField(label, cm: cm, unit: app.profile.lengthUnit)
        }
    }

    private func optionalField<Content: View>(
        _ label: String,
        included: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            Toggle(isOn: included) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text(included.wrappedValue ? "Included" : "Not logged")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                }
            }
            .tint(EvolvTheme.accent)
            .padding(.horizontal, 4)

            if included.wrappedValue {
                content()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: included.wrappedValue)
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
        guard hasAnyIncludedValue else { return }
        let existing = existingMeasurement
        let measurement = Measurement(
            id: existing?.id ?? UUID(),
            date: existing?.date ?? measurementDate ?? Date(),
            weightKg: includeWeight ? weightKg : nil,
            arms: includeArms ? armsCm : nil,
            chest: includeChest ? chestCm : nil,
            waist: includeWaist ? waistCm : nil,
            shoulders: includeShoulders ? shouldersCm : nil,
            thighs: includeThighs ? thighsCm : nil,
            scanID: scanID
        )
        do {
            try app.upsertMeasurement(measurement)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func initializeOnce() {
        guard !didInitialize else { return }
        didInitialize = true
        let existing = existingMeasurement
        let recent = app.measurements.last

        includeWeight = existing?.weightKg != nil
        includeArms = existing?.arms != nil
        includeChest = existing?.chest != nil
        includeWaist = existing?.waist != nil
        includeShoulders = existing?.shoulders != nil
        includeThighs = existing?.thighs != nil

        weightKg = existing?.weightKg ?? recent?.weightKg ?? app.profile.weightKg
        armsCm = existing?.arms ?? recent?.arms ?? app.profile.arms ?? 36
        chestCm = existing?.chest ?? recent?.chest ?? app.profile.chest ?? 100
        waistCm = existing?.waist ?? recent?.waist ?? app.profile.waist ?? 80
        shouldersCm = existing?.shoulders ?? recent?.shoulders ?? app.profile.shoulders ?? 110
        thighsCm = existing?.thighs ?? recent?.thighs ?? app.profile.thighs ?? 55
    }

    private func deleteExistingMeasurement() {
        guard let existingMeasurement else { return }
        do {
            try app.deleteMeasurement(id: existingMeasurement.id)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    HomeView().environment(AppState())
}
