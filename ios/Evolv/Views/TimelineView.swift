import SwiftUI

struct TimelineView: View {
    @Environment(AppState.self) private var app

    @State private var leftScanID: UUID? = nil
    @State private var rightScanID: UUID? = nil
    @State private var selectedPose: Pose = .front
    @State private var sliderPos: CGFloat = 0.5
    @State private var showFullscreen = false
    @State private var showLeftPicker = false
    @State private var showRightPicker = false

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
                .fullScreenCover(isPresented: $showFullscreen) {
                    if let left = scan(for: leftScanID), let right = scan(for: rightScanID) {
                        FullscreenComparisonView(left: left, right: right, pose: selectedPose)
                    }
                }
                .sheet(isPresented: $showLeftPicker) {
                    ScanPickerSheet(title: "Before", excluding: rightScanID) { id in
                        leftScanID = id
                        sliderPos = 0.5
                    }
                }
                .sheet(isPresented: $showRightPicker) {
                    ScanPickerSheet(title: "After", excluding: leftScanID) { id in
                        rightScanID = id
                        sliderPos = 0.5
                    }
                }
            }
        }
        .trackView("TimelineView")
    }

    @ViewBuilder
    private var content: some View {
        if app.scans.isEmpty {
            emptyState
        } else if app.scans.count == 1 {
            singleScanState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                comparisonHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                comparisonCard
                    .padding(.horizontal, 20)

                poseSelector
                    .padding(.horizontal, 20)

                timelineList
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Comparison header

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
        if l.id == app.firstScan?.id && r.id == app.latestScan?.id { return "Baseline → today" }
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

    // MARK: - Timeline list

    private var timelineList: some View {
        VStack(alignment: .leading, spacing: 12) {
            EvolvSectionHeader(title: "ALL SCANS", trailing: "\(app.scans.count) total")
            VStack(spacing: 10) {
                ForEach(app.scans.sorted { $0.date > $1.date }) { scan in
                    ScanRow(scan: scan)
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
        VStack(spacing: 18) {
            Spacer()
            if let scan = app.firstScan, let cap = scan.capture(for: .front) ?? scan.standardCaptures.first {
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
            VStack(spacing: 8) {
                Text("Baseline captured.")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Text("Your next scan will unlock the before-and-after comparison.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func scan(for id: UUID?) -> Scan? {
        guard let id else { return nil }
        return app.scans.first { $0.id == id }
    }

    private func defaultSelectionIfNeeded() {
        if leftScanID == nil { leftScanID = app.firstScan?.id }
        if rightScanID == nil { rightScanID = app.latestScan?.id }
        // Pick default pose available in both
        let poses = posesAvailableForBothScans()
        if !poses.contains(selectedPose), let first = poses.first { selectedPose = first }
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
    let onPick: (UUID) -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(app.scans.sorted { $0.date > $1.date }) { scan in
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
            ConfidenceChip(confidence: scan.consistencyScore > 78 ? .high : (scan.consistencyScore > 55 ? .medium : .low))
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
