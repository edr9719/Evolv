import SwiftUI

struct ScanDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let scanID: UUID
    @State private var galleryIndex: Int? = nil
    @State private var showRepairPicker = false
    @State private var repairRequest: CaptureRequest? = nil
    @State private var confirmDelete = false

    private var scan: Scan? { app.scan(id: scanID) }

    var body: some View {
        ZStack {
            AmbientBackground()
            if let scan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header(scan)
                        evidenceCard(scan)
                        photoSection(scan)
                        if let analysis = AnalysisStore.load(scanId: scan.id) {
                            PilotProgressContributionCard(scan: scan, analysis: analysis)
                        }
                        actionSection(scan)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
            } else {
                ContentUnavailableView("Scan unavailable", systemImage: "photo.on.rectangle")
            }
        }
        .navigationTitle("Scan details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRepairPicker) {
            if let scan {
                ScanRepairPickerSheet(
                    scanID: scan.id,
                    initiallySelected: scan.recommendedRepairPoses
                ) { poses in
                    repairRequest = .repair(scanID: scan.id, poses: poses)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(item: $repairRequest) { request in
            CaptureFlowView(
                scanRole: request.role,
                repairScanID: request.repairScanID,
                repairPoses: request.poses
            )
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { galleryIndex != nil },
                set: { if !$0 { galleryIndex = nil } }
            )
        ) {
            if let index = galleryIndex {
                FullscreenScanGallery(scanID: scanID, startingIndex: index)
            }
        }
        .alert("Delete this scan?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let scan {
                    app.deleteScan(scan)
                    dismiss()
                }
            }
        } message: {
            Text("This permanently removes every app photo and analysis record associated with this scan.")
        }
    }

    private func header(_ scan: Scan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scan.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text(scan.date, format: .dateTime.hour().minute())
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
                Spacer()
                Text(scan.resolvedRole == .canonical
                     ? (scan.analysisAvailability?.label ?? "Saved")
                     : scan.resolvedRole.label)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().stroke(EvolvTheme.stroke, lineWidth: 1))
            }
            Text("\(scan.captures.count) photo\(scan.captures.count == 1 ? "" : "s") · \(scan.standardCaptures.count) required · \(scan.showcaseCaptures.count) showcase")
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
        }
    }

    private func evidenceCard(_ scan: Scan) -> some View {
        GlassCard(padding: 18, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(scan.resolvedCaptureCompleteness == .complete ? "CAPTURE COMPLETE" : "CAPTURE INCOMPLETE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(EvolvTheme.accent)

                ForEach(Pose.required) { pose in
                    let capture = scan.capture(for: pose)
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: statusIcon(capture?.assessment?.status))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(statusColor(capture?.assessment?.status))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pose.label)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(EvolvTheme.text)
                            Text(capture?.assessment?.automaticStatusTitle ?? "Automatic check unavailable")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(EvolvTheme.textMuted)
                            if let detail = capture?.assessment?.automaticStatusDetail,
                               capture?.assessment?.status != .ready {
                                Text(detail)
                                    .font(.system(size: 11.5, design: .rounded))
                                    .foregroundStyle(EvolvTheme.textFaint)
                                    .lineSpacing(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func photoSection(_ scan: Scan) -> some View {
        let captures = orderedCaptures(scan)
        return VStack(alignment: .leading, spacing: 12) {
            EvolvSectionHeader(title: "ALL PHOTOS", trailing: "Tap to view")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(captures.enumerated()), id: \.element.id) { index, capture in
                    Button { galleryIndex = index } label: {
                        photoTile(capture)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func photoTile(_ capture: PoseCapture) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let image = PhotoStore.loadImage(named: capture.imageFilename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        EvolvTheme.surfaceHi
                        Image(systemName: "photo").foregroundStyle(EvolvTheme.textFaint)
                    }
                }
            }
            .frame(height: 230)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(capture.pose.label)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Text(capture.pose.category == .showcase
                     ? "Showcase only"
                     : (capture.assessment?.automaticStatusTitle ?? "Automatic check unavailable"))
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineLimit(2)
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 21).stroke(EvolvTheme.stroke, lineWidth: 1))
        }
    }

    private func actionSection(_ scan: Scan) -> some View {
        VStack(spacing: 12) {
            if scan.resolvedRole == .canonical {
                EvolvPrimaryButton(
                    title: scan.recommendedRepairPoses.isEmpty ? "Replace selected photos" : "Improve verification",
                    icon: "camera.fill"
                ) {
                    showRepairPicker = true
                }
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Text("Delete scan")
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.stalled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    private func orderedCaptures(_ scan: Scan) -> [PoseCapture] {
        scan.captures.sorted {
            (Pose.allCases.firstIndex(of: $0.pose) ?? Int.max)
                < (Pose.allCases.firstIndex(of: $1.pose) ?? Int.max)
        }
    }

    private func statusIcon(_ status: CaptureVerificationStatus?) -> String {
        switch status {
        case .ready: return "checkmark.circle.fill"
        case .reviewRecommended: return "exclamationmark.triangle.fill"
        case .unavailable, .none: return "eye.slash"
        }
    }

    private func statusColor(_ status: CaptureVerificationStatus?) -> Color {
        switch status {
        case .ready: return EvolvTheme.accent
        case .reviewRecommended: return EvolvTheme.stable
        case .unavailable, .none: return EvolvTheme.textMuted
        }
    }
}

struct FullscreenScanGallery: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let scanID: UUID
    @State private var selectedCaptureID: UUID?

    init(scanID: UUID, startingIndex: Int) {
        self.scanID = scanID
        _selectedCaptureID = State(initialValue: nil)
        self.startingIndex = startingIndex
    }

    private let startingIndex: Int

    private var captures: [PoseCapture] {
        guard let scan = app.scan(id: scanID) else { return [] }
        return scan.captures.sorted {
            (Pose.allCases.firstIndex(of: $0.pose) ?? Int.max)
                < (Pose.allCases.firstIndex(of: $1.pose) ?? Int.max)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !captures.isEmpty {
                TabView(selection: $selectedCaptureID) {
                    ForEach(captures) { capture in
                        ZoomableScanPhoto(capture: capture)
                            .tag(Optional(capture.id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    Spacer()
                    Text(counterText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                Spacer()
                if let capture = selectedCapture {
                    VStack(spacing: 4) {
                        Text(capture.pose.label)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(capture.pose.category == .showcase
                             ? "Showcase photo"
                             : (capture.assessment?.automaticStatusTitle ?? "Automatic check unavailable"))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    .padding(.bottom, 26)
                }
            }
        }
        .onAppear {
            guard selectedCaptureID == nil, !captures.isEmpty else { return }
            selectedCaptureID = captures[min(max(0, startingIndex), captures.count - 1)].id
        }
    }

    private var selectedCapture: PoseCapture? {
        captures.first { $0.id == selectedCaptureID }
    }

    private var counterText: String {
        guard let selectedCaptureID,
              let index = captures.firstIndex(where: { $0.id == selectedCaptureID }) else {
            return "\(captures.count) photos"
        }
        return "\(index + 1) of \(captures.count)"
    }
}

private struct ZoomableScanPhoto: View {
    let capture: PoseCapture
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image = PhotoStore.loadImage(named: capture.imageFilename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(scale)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(5, max(1, lastScale * value.magnification))
                    }
                    .onEnded { _ in lastScale = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    scale = scale > 1 ? 1 : 2
                    lastScale = scale
                }
            }
        }
    }
}
