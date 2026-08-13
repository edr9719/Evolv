import SwiftUI

private enum TimelineComparisonMode: String, CaseIterable, Identifiable {
    case baseline = "Baseline"
    case previous = "Previous"
    case custom = "Custom"

    var id: String { rawValue }
}

private struct TimelineMeasurementRequest: Identifiable {
    let scanID: UUID
    let date: Date
    var id: UUID { scanID }
}

struct TimelineView: View {
    @Environment(AppState.self) private var app

    @State private var leftScanID: UUID? = nil
    @State private var rightScanID: UUID? = nil
    @State private var selectedPose: Pose = .front
    @State private var sliderPos: CGFloat = 0.5
    @State private var showFullscreen = false
    @State private var showLeftPicker = false
    @State private var showRightPicker = false
    @State private var detailRequest: ScanDetailRequest? = nil
    @State private var pairComparison: ScanPairComparison? = nil
    @State private var comparisonMode: TimelineComparisonMode = .baseline
    @State private var measurementRequest: TimelineMeasurementRequest? = nil

    var body: some View {
        Group {
            NavigationStack {
                ZStack {
                    AmbientBackground()
                    content
                }
                .navigationTitle("Timeline")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear(perform: defaultSelectionIfNeeded)
                .onChange(of: app.activeCaptureRecipe?.id) { _, _ in
                    leftScanID = nil
                    rightScanID = nil
                    comparisonMode = .baseline
                    defaultSelectionIfNeeded()
                }
                .onChange(of: app.latestAnalysis?.analyzedAt) { _, _ in
                    refreshPairComparison()
                }
                .fullScreenCover(isPresented: $showFullscreen) {
                    if let left = scan(for: leftScanID), let right = scan(for: rightScanID) {
                        FullscreenComparisonView(left: left, right: right, pose: selectedPose)
                    }
                }
                .sheet(isPresented: $showLeftPicker) {
                    ScanPickerSheet(
                        title: "Before",
                        excluding: rightScanID,
                        recipeID: app.activeCaptureRecipe?.id
                    ) { id in
                        selectScan(id, asBefore: true)
                    }
                }
                .sheet(isPresented: $showRightPicker) {
                    ScanPickerSheet(
                        title: "After",
                        excluding: leftScanID,
                        recipeID: app.activeCaptureRecipe?.id
                    ) { id in
                        selectScan(id, asBefore: false)
                    }
                }
                .sheet(item: $detailRequest) { request in
                    NavigationStack { ScanDetailView(scanID: request.id) }
                }
                .sheet(item: $measurementRequest) { request in
                    LogMeasurementSheet(scanID: request.scanID, measurementDate: request.date)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
        .trackView("TimelineView")
    }

    @ViewBuilder
    private var content: some View {
        if app.activeCanonicalScans.isEmpty {
            emptyState
        } else if app.activeCanonicalScans.count <= 1 {
            singleScanState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                comparisonModePicker
                    .padding(.horizontal, 20)

                comparisonHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                comparisonCard
                    .padding(.horizontal, 20)

                comparisonNarrativeCard
                    .padding(.horizontal, 20)

                measurementComparisonCard
                    .padding(.horizontal, 20)

                poseSelector
                    .padding(.horizontal, 20)

                comparisonEvidenceCard
                    .padding(.horizontal, 20)

                timelineList
                    .padding(.horizontal, 24)

                validationSessionSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Comparison header

    private var comparisonModePicker: some View {
        HStack(spacing: 6) {
            ForEach(TimelineComparisonMode.allCases) { mode in
                Button {
                    applyComparisonMode(mode)
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(comparisonMode == mode ? EvolvTheme.background : EvolvTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            Capsule().fill(comparisonMode == mode ? EvolvTheme.accent : EvolvTheme.surface)
                                .overlay(Capsule().stroke(comparisonMode == mode ? .clear : EvolvTheme.stroke, lineWidth: 1))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comparison range")
    }

    private var comparisonHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EVOLUTION")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(EvolvTheme.textFaint)
            HStack(alignment: .firstTextBaseline) {
                Text(headlineForComparison)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Spacer()
                if let l = scan(for: leftScanID), let r = scan(for: rightScanID) {
                    let days = Calendar.current.dateComponents([.day], from: l.date, to: r.date).day ?? 0
                    Text("\(days) days apart")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headlineForComparison: String {
        guard let l = scan(for: leftScanID), let r = scan(for: rightScanID) else { return "Compare your scans" }
        if l.id == app.activeBaselineScan?.id && r.id == app.activeLatestScan?.id { return "Baseline → today" }
        if comparisonMode == .previous { return "Previous → today" }
        return "Side by side"
    }

    // MARK: - Comparison card with reveal slider

    private var comparisonCard: some View {
        let left = scan(for: leftScanID)
        let right = scan(for: rightScanID)
        let leftCapture = left?.capture(for: selectedPose) ?? left?.standardCaptures.first
        let rightCapture = right?.capture(for: selectedPose) ?? right?.standardCaptures.first

        return GlassCard(padding: 12, cornerRadius: 26) {
            VStack(spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // BEFORE
                        ComparisonImage(capture: leftCapture, label: "BEFORE", date: left?.date)
                            .frame(width: geo.size.width, height: geo.size.height)
                        // AFTER (clipped)
                        ComparisonImage(capture: rightCapture, label: "AFTER", date: right?.date, isAfter: true)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .mask(
                                HStack(spacing: 0) {
                                    Color.clear.frame(width: geo.size.width * sliderPos)
                                    Color.black
                                }
                            )
                        // Divider + handle
                        Rectangle()
                            .fill(EvolvTheme.accent)
                            .frame(width: 2)
                            .shadow(color: EvolvTheme.accent.opacity(0.7), radius: 8)
                            .offset(x: geo.size.width * sliderPos - 1)
                        ZStack {
                            Circle().fill(EvolvTheme.accent).frame(width: 38, height: 38)
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(EvolvTheme.background)
                        }
                        .shadow(color: EvolvTheme.accent.opacity(0.5), radius: 10)
                        .offset(x: geo.size.width * sliderPos - 19, y: geo.size.height / 2 - 19)
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    let x = min(max(0, v.location.x), geo.size.width)
                                    withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) {
                                        sliderPos = x / geo.size.width
                                    }
                                }
                        )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { showFullscreen = true }
                }
                .frame(height: 440)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 10) {
                    pickerChip(title: "Before", scan: left) { showLeftPicker = true }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EvolvTheme.textFaint)
                    pickerChip(title: "After", scan: right) { showRightPicker = true }
                    Spacer()
                    Button { showFullscreen = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(EvolvTheme.text.opacity(0.75))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(EvolvTheme.surface).overlay(Circle().stroke(EvolvTheme.stroke, lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pickerChip(title: String, scan: Scan?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(EvolvTheme.accent)
                if let date = scan?.date {
                    Text(date, format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                } else {
                    Text("—").foregroundStyle(EvolvTheme.textFaint)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(EvolvTheme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(EvolvTheme.surface)
                    .overlay(Capsule().stroke(EvolvTheme.stroke, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pose selector

    private var poseSelector: some View {
        let availablePoses: [Pose] = posesAvailableForBothScans()
        return VStack(alignment: .leading, spacing: 10) {
            Text("POSE")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(EvolvTheme.textFaint)
                .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availablePoses) { pose in
                        let selected = selectedPose == pose
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedPose = pose }
                        } label: {
                            Text(pose.shortLabel)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(selected ? EvolvTheme.background : EvolvTheme.text)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background {
                                    Capsule().fill(selected ? EvolvTheme.accent : EvolvTheme.surface)
                                        .overlay(Capsule().stroke(selected ? .clear : EvolvTheme.stroke, lineWidth: 1))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func posesAvailableForBothScans() -> [Pose] {
        guard let l = scan(for: leftScanID), let r = scan(for: rightScanID) else { return Pose.required }
        return Pose.allCases.filter { pose in
            l.capture(for: pose) != nil && r.capture(for: pose) != nil
        }
    }

    private var comparisonEvidenceCard: some View {
        let narrative = app.comparisonNarrative(for: pairComparison, pose: selectedPose)
        return ComparisonEvidenceCard(
            comparison: pairComparison,
            narrative: narrative,
            pose: selectedPose,
            analysisIsPending: app.analysisPending
        )
    }

    private var comparisonNarrativeCard: some View {
        ComparisonNarrativeCard(
            narrative: app.comparisonNarrative(for: pairComparison),
            analysisIsPending: app.analysisPending
        )
    }

    private var measurementComparisonCard: some View {
        MeasurementComparisonCard(
            comparison: app.measurementComparison(
                beforeID: leftScanID,
                afterID: rightScanID,
                visualComparison: pairComparison
            ),
            beforeScan: scan(for: leftScanID),
            afterScan: scan(for: rightScanID),
            onEdit: { scan in
                measurementRequest = TimelineMeasurementRequest(scanID: scan.id, date: scan.date)
            }
        )
    }

    // MARK: - Timeline list

    private var timelineList: some View {
        let visibleScans = app.scans
            .filter { !$0.isValidationOnlyScan }
            .sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 12) {
            EvolvSectionHeader(title: "ALL SCANS", trailing: "\(visibleScans.count) total")
            VStack(spacing: 10) {
                ForEach(visibleScans) { scan in
                    Button {
                        detailRequest = ScanDetailRequest(id: scan.id)
                    } label: {
                        ScanRow(scan: scan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var validationSessionSection: some View {
        let sessions = app.validationSessions.sorted { $0.startedAt > $1.startedAt }
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                EvolvSectionHeader(title: "CONSISTENCY TESTS", trailing: "\(sessions.count)")
                Text("Grouped separately. Consistency repeats never affect your baseline, progress, reminders, or streak.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
                    .lineSpacing(2)
                ForEach(sessions) { session in
                    ValidationTimelineCard(
                        session: session,
                        scans: app.validationScans(sessionID: session.id),
                        onOpenScan: { scanID in
                            detailRequest = ScanDetailRequest(id: scanID)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Empty / single state

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(EvolvTheme.accent.opacity(0.10)).frame(width: 180, height: 180).blur(radius: 24)
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(EvolvTheme.accent)
            }
            VStack(spacing: 8) {
                Text("Your timeline starts with your first scan.")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .multilineTextAlignment(.center)
                Text("Capture three angles to set your baseline. Comparisons unlock as scans accumulate.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var singleScanState: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let scan = app.activeBaselineScan, let cap = scan.capture(for: .front) ?? scan.standardCaptures.first {
                    Button {
                        detailRequest = ScanDetailRequest(id: scan.id)
                    } label: {
                        ZStack {
                            if let img = PhotoStore.loadImage(named: cap.imageFilename) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 240, height: 360)
                                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            }
                            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .frame(width: 240, height: 360)
                            VStack {
                                Spacer()
                                Text("BASELINE")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .tracking(1.4)
                                    .foregroundStyle(EvolvTheme.accent)
                                Text(scan.date, format: .dateTime.day().month(.wide).year())
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .padding(.bottom, 16)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(EvolvTheme.stroke, lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 8) {
                    Text("Baseline captured.")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text("Your next progress scan will unlock the before-and-after comparison.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Text("Tap the baseline to view all \(app.activeBaselineScan?.captures.count ?? 0) photos")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                }

                let extras = app.scans
                    .filter { !$0.isCanonicalProgressScan && !$0.isValidationOnlyScan }
                    .sorted { $0.date > $1.date }
                if !extras.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        EvolvSectionHeader(title: "SAME-DAY EXTRAS", trailing: "\(extras.count)")
                        ForEach(extras) { scan in
                            Button {
                                detailRequest = ScanDetailRequest(id: scan.id)
                            } label: {
                                ScanRow(scan: scan)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                let previousSetups = app.canonicalScans
                    .filter { $0.captureRecipeID != app.activeCaptureRecipe?.id }
                    .sorted { $0.date > $1.date }
                if !previousSetups.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        EvolvSectionHeader(title: "PREVIOUS BASELINE SETUPS", trailing: "\(previousSetups.count)")
                        Text("These scans remain saved, but a different camera recipe keeps them out of the current automatic comparison.")
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(EvolvTheme.textFaint)
                            .lineSpacing(2)
                        ForEach(previousSetups) { scan in
                            Button {
                                detailRequest = ScanDetailRequest(id: scan.id)
                            } label: {
                                ScanRow(scan: scan)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                validationSessionSection
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }
            .padding(.top, 32)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Helpers

    private func scan(for id: UUID?) -> Scan? {
        guard let id else { return nil }
        return app.scans.first { $0.id == id }
    }

    private func defaultSelectionIfNeeded() {
        let activeIDs = Set(app.activeCanonicalScans.map(\.id))
        if let leftScanID, !activeIDs.contains(leftScanID) { self.leftScanID = nil }
        if let rightScanID, !activeIDs.contains(rightScanID) { self.rightScanID = nil }
        if leftScanID == nil || rightScanID == nil {
            applyComparisonMode(comparisonMode)
            return
        }
        // Pick default pose available in both
        let poses = posesAvailableForBothScans()
        if !poses.contains(selectedPose), let first = poses.first { selectedPose = first }
        refreshPairComparison()
    }

    private func selectScan(_ id: UUID, asBefore: Bool) {
        comparisonMode = .custom
        let selected = scan(for: id)
        let other = scan(for: asBefore ? rightScanID : leftScanID)
        if let selected, let other {
            if selected.date < other.date {
                leftScanID = selected.id
                rightScanID = other.id
            } else {
                leftScanID = other.id
                rightScanID = selected.id
            }
        } else if asBefore {
            leftScanID = id
        } else {
            rightScanID = id
        }
        let poses = posesAvailableForBothScans()
        if !poses.contains(selectedPose), let first = poses.first { selectedPose = first }
        sliderPos = 0.5
        refreshPairComparison()
    }

    private func applyComparisonMode(_ mode: TimelineComparisonMode) {
        comparisonMode = mode
        let active = app.activeCanonicalScans.sorted { $0.date < $1.date }
        switch mode {
        case .baseline:
            leftScanID = active.first?.id
            rightScanID = active.last?.id
        case .previous:
            leftScanID = active.dropLast().last?.id ?? active.first?.id
            rightScanID = active.last?.id
        case .custom:
            if leftScanID == nil { leftScanID = active.first?.id }
            if rightScanID == nil { rightScanID = active.last?.id }
        }
        let poses = posesAvailableForBothScans()
        if !poses.contains(selectedPose), let first = poses.first { selectedPose = first }
        sliderPos = 0.5
        refreshPairComparison()
    }

    private func refreshPairComparison() {
        pairComparison = app.comparison(beforeID: leftScanID, afterID: rightScanID)
    }
}

// MARK: - Truthful selected-pair evidence

private struct ComparisonEvidenceCard: View {
    let comparison: ScanPairComparison?
    let narrative: ComparisonNarrative
    let pose: Pose
    let analysisIsPending: Bool

    private var poseComparison: PoseComparison? {
        comparison?.comparison(for: pose)
    }

    private var supported: [RegionalComparison] {
        if pose.category == .standard {
            return comparison?.relaxedRegions.filter { $0.status != .unavailable } ?? []
        }
        return poseComparison?.supportedRegions ?? []
    }

    var body: some View {
        GlassCard(padding: 18, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(EvolvTheme.accent)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                        Text(detail)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 0)
                }

                if comparison != nil, !supported.isEmpty {
                    Divider().overlay(EvolvTheme.stroke)
                    ForEach(supported, id: \.region) { result in
                        resultRow(result)
                    }
                    HStack {
                        Text("EVIDENCE STRENGTH")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(EvolvTheme.textFaint)
                        Spacer()
                        Text(narrative.evidenceStrength.label)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.accent)
                    }
                }

                Text(caveat)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
                    .lineSpacing(2)
            }
        }
    }

    private var headline: String {
        if analysisIsPending { return "Preparing this comparison" }
        return narrative.headline
    }

    private var detail: String {
        if analysisIsPending {
            return "Evolv is rebuilding local evidence. Your photos remain available while this finishes."
        }
        return narrative.detail
    }

    private var caveat: String {
        narrative.limitations.joined(separator: " ")
    }

    private var statusIcon: String {
        if analysisIsPending { return "hourglass" }
        guard !supported.isEmpty else { return "viewfinder.circle" }
        return supported.allSatisfy { $0.status == .stable }
            ? "equal.circle.fill"
            : "waveform.path.ecg"
    }

    private func resultRow(_ result: RegionalComparison) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color(for: result.status))
                .frame(width: 7, height: 7)
            Text(result.region.visualLabel(for: pose.category == .showcase ? pose : nil))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
            Spacer(minLength: 8)
            Text(resultText(result))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(color(for: result.status))
        }
    }

    private func resultText(_ result: RegionalComparison) -> String {
        switch result.status {
        case .stable:
            return "Stable"
        case .increase:
            guard let delta = result.normalizedDelta else { return "Increased" }
            return String(format: "+%.1f%% normalized", abs(delta) * 100)
        case .decrease:
            guard let delta = result.normalizedDelta else { return "Decreased" }
            return String(format: "−%.1f%% normalized", abs(delta) * 100)
        case .unavailable:
            return "Unavailable"
        }
    }

    private func color(for status: RegionalComparisonStatus) -> Color {
        switch status {
        case .stable: return EvolvTheme.accent
        case .increase, .decrease: return EvolvTheme.stable
        case .unavailable: return EvolvTheme.textMuted
        }
    }
}

/// The product-level answer for the exact selected pair. The technical
/// pose-by-pose evidence remains directly below it for inspection.
private struct ComparisonNarrativeCard: View {
    let narrative: ComparisonNarrative
    let analysisIsPending: Bool

    var body: some View {
        GlassCard(padding: 20, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EvolvTheme.accent)
                    Text("EVOLV READ")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(EvolvTheme.textFaint)
                    Spacer()
                    Text(narrative.evidenceStrength.label)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                }

                Text(analysisIsPending ? "Preparing an exact-pair result" : narrative.headline)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(analysisIsPending
                     ? "Evolv is rebuilding the local evidence for these scans. No temporary guess is shown."
                     : narrative.detail)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)

                if !analysisIsPending, let limitation = narrative.limitations.first {
                    Divider().overlay(EvolvTheme.stroke)
                    Text(limitation)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                        .lineSpacing(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Evolv comparison summary")
    }
}

/// User-entered weight/tape facts for the exact selected pair. This card is
/// deliberately separate from EVOLV READ because circumference and normalized
/// 2D silhouette are different quantities.
private struct MeasurementComparisonCard: View {
    let comparison: ScanPairMeasurementComparison?
    let beforeScan: Scan?
    let afterScan: Scan?
    let onEdit: (Scan) -> Void

    private var visibleResults: [LoggedMeasurementComparison] {
        comparison?.results.filter { $0.beforeValue != nil || $0.afterValue != nil } ?? []
    }

    var body: some View {
        GlassCard(padding: 18, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Image(systemName: "ruler")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EvolvTheme.accent)
                    Text("LOGGED MEASUREMENTS")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(EvolvTheme.textFaint)
                    Spacer()
                    Text("Exact entries")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                }

                Text(summary)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(2)

                if !visibleResults.isEmpty {
                    Divider().overlay(EvolvTheme.stroke)
                    ForEach(visibleResults) { result in
                        if result.status == .unavailable {
                            unavailableRow(result)
                        } else {
                            LoggedMeasurementDeltaRow(result: result)
                                .padding(.horizontal, -18)
                        }
                    }
                }

                if beforeScan != nil || afterScan != nil {
                    Divider().overlay(EvolvTheme.stroke)
                    HStack(spacing: 10) {
                        if let beforeScan {
                            editButton(
                                title: comparison?.beforeMeasurementID == nil ? "Add before" : "Edit before",
                                scan: beforeScan
                            )
                        }
                        if let afterScan {
                            editButton(
                                title: comparison?.afterMeasurementID == nil ? "Add after" : "Edit after",
                                scan: afterScan
                            )
                        }
                    }
                }

                Text("Direction agreement is shown only as context. It does not turn a photo silhouette into inches or strengthen automatic visual evidence.")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
                    .lineSpacing(2)
            }
        }
    }

    private var summary: String {
        guard let comparison else {
            return "Select two scans to compare the values you entered for each one."
        }
        if comparison.hasBothMeasurements, !comparison.supportedResults.isEmpty {
            return "These changes use only the values you entered for the selected before and after scans."
        }
        if comparison.hasBothMeasurements {
            return "Both scans have entries, but no matching value was logged on both sides."
        }
        return "Add values to both scans to see a truthful numeric change. Evolv will not match older entries by date or estimate missing values from photos."
    }

    private func unavailableRow(_ result: LoggedMeasurementComparison) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.metric.label)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
            Text(result.unavailableReason ?? "Not available for both scans.")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(EvolvTheme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }

    private func editButton(title: String, scan: Scan) -> some View {
        Button { onEdit(scan) } label: {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    Capsule()
                        .fill(EvolvTheme.accentDim)
                        .overlay(Capsule().stroke(EvolvTheme.accent.opacity(0.35), lineWidth: 1))
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Local consistency-test group

private struct ValidationTimelineCard: View {
    let session: ValidationStudySession
    let scans: [Scan]
    let onOpenScan: (UUID) -> Void

    private var statusTitle: String {
        switch session.status {
        case .active: return "In progress"
        case .evaluating: return "Evaluating locally"
        case .completed: return session.result?.title ?? "Complete"
        case .protocolIneligible: return "Protocol incomplete"
        case .abandoned: return "Stopped"
        }
    }

    private var statusIcon: String {
        switch session.status {
        case .active: return "camera.fill"
        case .evaluating: return "hourglass"
        case .completed:
            switch session.result {
            case .consistent: return "checkmark.seal.fill"
            case .limitedEvidence: return "viewfinder.circle"
            case .needsReview: return "exclamationmark.triangle.fill"
            case .none: return "checkmark.circle"
            }
        case .protocolIneligible, .abandoned: return "clock.badge.exclamationmark"
        }
    }

    var body: some View {
        GlassCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(EvolvTheme.accent)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                        Text(session.startedAt, format: .dateTime.weekday(.wide).day().month(.abbreviated).hour().minute())
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                    }
                    Spacer()
                    Text("\(session.completedSetCount)/5")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                }

                HStack(spacing: 8) {
                    ForEach(1...ValidationStudySession.requiredSetCount, id: \.self) { setNumber in
                        if let scan = scans.first(where: { $0.validationSetNumber == setNumber }) {
                            Button {
                                onOpenScan(scan.id)
                            } label: {
                                validationSetThumbnail(scan: scan, setNumber: setNumber)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open consistency Set \(setNumber)")
                        } else {
                            validationSetPlaceholder(setNumber: setNumber)
                        }
                    }
                }

                Text("Uses the \(session.lockedCameraPosition.label.lowercased()) camera · saved only on this iPhone")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
            }
        }
    }

    private func validationSetThumbnail(scan: Scan, setNumber: Int) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(EvolvTheme.surfaceHi)
            if let capture = scan.capture(for: .front),
               let image = PhotoStore.loadImage(named: capture.imageFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            Text("SET \(setNumber)")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.white)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(EvolvTheme.stroke, lineWidth: 1))
    }

    private func validationSetPlaceholder(setNumber: Int) -> some View {
        VStack(spacing: 5) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 15))
            Text("SET \(setNumber)")
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(EvolvTheme.textFaint)
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .background(RoundedRectangle(cornerRadius: 11).fill(EvolvTheme.surfaceHi))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(EvolvTheme.stroke, lineWidth: 1))
    }
}

// MARK: - Comparison image

struct ComparisonImage: View {
    let capture: PoseCapture?
    let label: String
    let date: Date?
    var isAfter: Bool = false

    var body: some View {
        ZStack {
            if let capture, let img = PhotoStore.loadImage(named: capture.imageFilename) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.07, green: 0.09, blue: 0.09),
                             Color(red: 0.04, green: 0.05, blue: 0.05)],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(spacing: 8) {
                    Image(systemName: "camera").font(.system(size: 28, weight: .light))
                        .foregroundStyle(EvolvTheme.textFaint)
                    Text("No photo for this pose")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                }
            }
            // Top tag
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(isAfter ? EvolvTheme.accent : .white)
                        if let date {
                            Text(date, format: .dateTime.day().month(.abbreviated).year())
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ultraThinMaterial))
                    Spacer()
                }
                .padding(.top, 10)
                .padding(.leading, 10)
                Spacer()
            }
        }
        .clipped()
    }
}

// MARK: - Fullscreen comparison

struct FullscreenComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let left: Scan
    let right: Scan
    let pose: Pose
    @State private var sliderPos: CGFloat = 0.5
    @State private var sideBySide = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            // Top bar
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    Spacer()
                    Button { withAnimation { sideBySide.toggle() } } label: {
                        Image(systemName: sideBySide ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                Spacer()
                // Bottom dates
                HStack {
                    dateBadge(label: "BEFORE", date: left.date)
                    Spacer()
                    dateBadge(label: "AFTER", date: right.date, accent: true)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let l = left.capture(for: pose) ?? left.standardCaptures.first
        let r = right.capture(for: pose) ?? right.standardCaptures.first
        if sideBySide {
            HStack(spacing: 2) {
                fullImage(l)
                fullImage(r)
            }
            .ignoresSafeArea()
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    fullImage(l).frame(width: geo.size.width, height: geo.size.height)
                    fullImage(r)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .mask(
                            HStack(spacing: 0) {
                                Color.clear.frame(width: geo.size.width * sliderPos)
                                Color.black
                            }
                        )
                    Rectangle()
                        .fill(EvolvTheme.accent)
                        .frame(width: 2)
                        .shadow(color: EvolvTheme.accent.opacity(0.7), radius: 10)
                        .offset(x: geo.size.width * sliderPos - 1)
                    ZStack {
                        Circle().fill(EvolvTheme.accent).frame(width: 44, height: 44)
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(EvolvTheme.background)
                    }
                    .shadow(color: EvolvTheme.accent.opacity(0.5), radius: 14)
                    .offset(x: geo.size.width * sliderPos - 22, y: geo.size.height / 2 - 22)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                let x = min(max(0, v.location.x), geo.size.width)
                                sliderPos = x / geo.size.width
                            }
                    )
                }
            }
            .ignoresSafeArea()
        }
    }

    private func fullImage(_ capture: PoseCapture?) -> some View {
        Group {
            if let capture, let img = PhotoStore.loadImage(named: capture.imageFilename) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.black
            }
        }
        .clipped()
    }

    private func dateBadge(label: String, date: Date, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(accent ? EvolvTheme.accent : .white)
            Text(date, format: .dateTime.day().month(.abbreviated).year())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial))
    }
}

// MARK: - Scan picker sheet

struct ScanPickerSheet: View {
    let title: String
    let excluding: UUID?
    let recipeID: UUID?
    let onPick: (UUID) -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(app.canonicalScans.filter { $0.captureRecipeID == recipeID }.sorted { $0.date > $1.date }) { scan in
                            if scan.id != excluding {
                                Button {
                                    onPick(scan.id)
                                    dismiss()
                                } label: {
                                    scanTile(scan)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Select \(title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.tint(EvolvTheme.accent)
                }
            }
        }
    }

    private func scanTile(_ scan: Scan) -> some View {
        let cap = scan.capture(for: .front) ?? scan.standardCaptures.first
        return ZStack(alignment: .bottomLeading) {
            if let cap, let img = PhotoStore.loadImage(named: cap.imageFilename) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(EvolvTheme.surface)
                    .frame(height: 200)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(height: 200)
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(scan.captures.count) photo\(scan.captures.count == 1 ? "" : "s")")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(12)
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(EvolvTheme.stroke, lineWidth: 1))
    }
}

// MARK: - Scan row (in list)

struct ScanRow: View {
    let scan: Scan
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(EvolvTheme.surfaceHi)
                    .frame(width: 56, height: 72)
                if let cap = scan.capture(for: .front) ?? scan.standardCaptures.first,
                   let img = PhotoStore.loadImage(named: cap.imageFilename) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(EvolvTheme.textFaint)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                HStack(spacing: 8) {
                    Text("\(scan.captures.count) photo\(scan.captures.count == 1 ? "" : "s")")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                    if scan.showcaseCaptures.count > 0 {
                        Text("·").foregroundStyle(EvolvTheme.textFaint)
                        Text("\(scan.showcaseCaptures.count) showcase")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(EvolvTheme.accent)
                    }
                }
            }
            Spacer()
            Text(scan.analysisAvailability?.label ?? "Legacy")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(scan.analysisAvailability == .comparable ? EvolvTheme.accent : EvolvTheme.textMuted)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().stroke(EvolvTheme.stroke, lineWidth: 1))
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(EvolvTheme.stroke, lineWidth: 1)
                }
        }
    }
}

#Preview { TimelineView().environment(AppState()) }
