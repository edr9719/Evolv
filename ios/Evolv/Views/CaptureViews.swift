import SwiftUI
import PhotosUI
import UIKit

// MARK: - Capture launch (tab entry)

struct CaptureLaunchView: View {
    @State private var showFlow = false
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("GUIDED SCAN")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .tracking(1.6)
                                .foregroundStyle(EvolvTheme.accent)
                            Text(app.hasAnyScans ? "Capture today's scan" : "Capture your baseline")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(EvolvTheme.text)
                            Text("Three angles. Same room. Same lighting. Same distance. Evolv compares each scan against your baseline.")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(EvolvTheme.textMuted)
                                .lineSpacing(3)
                        }

                        VStack(spacing: 10) {
                            ForEach(Pose.required) { pose in
                                PoseRow(pose: pose, completed: false)
                            }
                        }

                        if let last = app.latestScan {
                            GlassCard(padding: 18, cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("LAST SCAN")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .tracking(1.4)
                                        .foregroundStyle(EvolvTheme.textFaint)
                                    HStack(spacing: 20) {
                                        scoreStat("Lighting", value: last.lightingScore)
                                        scoreStat("Framing", value: last.framingScore)
                                        scoreStat("Consistency", value: last.consistencyScore)
                                    }
                                    Text("Match these conditions as closely as possible.")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(EvolvTheme.textMuted)
                                }
                            }
                        }

                        EvolvPrimaryButton(title: "Start guided capture", icon: "camera.fill") {
                            showFlow = true
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showFlow) {
                CaptureFlowView()
            }
        }
    }

    private func scoreStat(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(EvolvTheme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PoseRow: View {
    let pose: Pose
    let completed: Bool
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(EvolvTheme.accentDim)
                    .frame(width: 52, height: 52)
                Image(systemName: pose.icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(EvolvTheme.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(pose.label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Text(pose.subtitle)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
            }
            Spacer()
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(completed ? EvolvTheme.accent : EvolvTheme.textFaint)
        }
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
}

// MARK: - Capture flow

struct CaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app

    enum Phase { case standard, askShowcase, showcase, finalizing, result }

    @State private var phase: Phase = .standard
    @State private var poseIndex = 0
    @State private var captures: [PoseCapture] = []

    // showcase
    @State private var showcaseQueue: [Pose] = []
    @State private var showcaseIndex = 0

    // photo picker / camera
    @State private var showCameraSheet: Bool = false
    @State private var showLibraryPicker: Bool = false
    @State private var libraryItem: PhotosPickerItem? = nil

    // Quality gate
    @State private var pendingImage: UIImage? = nil
    @State private var pendingPose: Pose? = nil
    @State private var qualityIssues: [QualityIssue] = []
    @State private var showQualityAlert: Bool = false
    @State private var isAnalyzing: Bool = false
    @State private var loadError: String? = nil
    @State private var showLoadError: Bool = false

    // UX state
    @State private var showCancelConfirmation: Bool = false
    @State private var justCapturedPose: Pose? = nil

    private var standardPoses: [Pose] { Pose.required }

    var body: some View {
        ZStack {
            AmbientBackground()
            content
                .animation(.easeInOut(duration: 0.3), value: phase)
                .animation(.easeInOut(duration: 0.3), value: poseIndex)
                .animation(.easeInOut(duration: 0.3), value: showcaseIndex)

            if isAnalyzing {
                analyzingOverlay
                    .transition(.opacity)
            }

            if justCapturedPose != nil {
                captureSuccessFlash
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAnalyzing)
        .animation(.easeInOut(duration: 0.2), value: justCapturedPose != nil)
        .fullScreenCover(isPresented: $showCameraSheet) {
            if let pose = resolvedCurrentPose {
                TimerCameraView(pose: pose) { image in
                    handleCaptured(image: image)
                }
            }
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $libraryItem, matching: .images, photoLibrary: .shared())
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            isAnalyzing = true
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            libraryItem = nil
                            handleCaptured(image: img)
                        }
                    } else {
                        await MainActor.run {
                            libraryItem = nil
                            isAnalyzing = false
                            loadError = "We couldn't load that photo. Try a different one from your library."
                            showLoadError = true
                        }
                    }
                } catch {
                    await MainActor.run {
                        libraryItem = nil
                        isAnalyzing = false
                        loadError = "We couldn't load that photo. Try a different one from your library."
                        showLoadError = true
                    }
                }
            }
        }
        .alert("Couldn't load photo", isPresented: $showLoadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadError ?? "Try a different photo.")
        }
        .alert("Photo Quality Warning", isPresented: $showQualityAlert) {
            Button("Retake") {
                let issue = qualityIssues.first
                pendingImage = nil
                pendingPose = nil
                qualityIssues = []
                // Auto-reopen camera after alert dismisses
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showCameraSheet = true
                }
                _ = issue
            }
            Button("Use Anyway") {
                if let img = pendingImage, let pose = pendingPose {
                    commitCapture(image: img, pose: pose)
                }
                pendingImage = nil
                pendingPose = nil
                qualityIssues = []
            }
        } message: {
            let hint = qualityIssues.first?.retakeHint ?? ""
            Text((qualityIssues.first?.userMessage ?? "Photo quality may affect analysis accuracy.") + (hint.isEmpty ? "" : " \(hint)"))
        }
        .alert("Discard scan?", isPresented: $showCancelConfirmation) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) {}
        } message: {
            let count = captures.count
            Text("You've captured \(count) pose\(count == 1 ? "" : "s"). Discarding will delete this session.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .standard:
            posePromptView(
                pose: standardPoses[poseIndex],
                stepLabel: "POSE \(poseIndex + 1) OF \(standardPoses.count)",
                isShowcase: false,
                isLastInPhase: poseIndex == standardPoses.count - 1
            )
        case .askShowcase:
            askShowcaseView
        case .showcase:
            posePromptView(
                pose: showcaseQueue[showcaseIndex],
                stepLabel: "SHOWCASE \(showcaseIndex + 1) OF \(showcaseQueue.count)",
                isShowcase: true,
                isLastInPhase: showcaseIndex == showcaseQueue.count - 1
            )
        case .finalizing:
            ProgressView()
                .tint(EvolvTheme.accent)
                .scaleEffect(1.4)
        case .result:
            CaptureResultView(onDone: { dismiss() })
        }
    }

    // MARK: - Pose prompt

    private func posePromptView(pose: Pose, stepLabel: String, isShowcase: Bool, isLastInPhase: Bool) -> some View {
        VStack(spacing: 0) {
            topBar(stepLabel: stepLabel, pose: pose)

            Spacer(minLength: 8)

            // Silhouette preview matching the pose
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(EvolvTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(EvolvTheme.stroke, lineWidth: 1)
                    }
                SilhouetteShape(pose: pose)
                    .stroke(EvolvTheme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(width: 200, height: 380)
                    .shadow(color: EvolvTheme.accent.opacity(0.4), radius: 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 460)
            .padding(.horizontal, 24)

            // Completed pose thumbnails
            let standardCaptures = captures.filter { $0.pose.category == .standard }
            if !standardCaptures.isEmpty {
                HStack(spacing: 8) {
                    ForEach(standardCaptures) { c in
                        ZStack(alignment: .bottomLeading) {
                            if let img = PhotoStore.loadImage(named: c.imageFilename) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 48, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(EvolvTheme.surface)
                                    .frame(width: 48, height: 64)
                            }
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(EvolvTheme.accent)
                                .padding(4)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(EvolvTheme.accent.opacity(0.5), lineWidth: 1)
                        )
                    }
                }
                .padding(.top, 14)
            }

            VStack(spacing: 6) {
                Text(pose.label)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Text(pose.subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, standardCaptures.isEmpty ? 18 : 10)

            Spacer()

            VStack(spacing: 12) {
                EvolvPrimaryButton(title: "Take photo", icon: "camera.fill") {
                    showCameraSheet = true
                }
                Button { showLibraryPicker = true } label: {
                    Text("Choose from library")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
                .buttonStyle(.plain)

                if isShowcase {
                    Button { skipShowcase() } label: {
                        Text(isLastInPhase ? "Skip and finish" : "Skip this pose")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(EvolvTheme.textFaint)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private func topBar(stepLabel: String, pose: Pose) -> some View {
        HStack {
            Button {
                if captures.isEmpty {
                    dismiss()
                } else {
                    showCancelConfirmation = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EvolvTheme.text)
                    .padding(10)
                    .background(Circle().fill(EvolvTheme.surface))
                    .overlay(Circle().stroke(EvolvTheme.stroke, lineWidth: 1))
            }
            Spacer()
            VStack(spacing: 2) {
                Text(stepLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(EvolvTheme.accent)
                Text(pose.shortLabel)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
            }
            Spacer()
            // Progress bar
            let doneCount = Double(captures.filter { $0.pose.category == .standard }.count)
            let totalCount = Double(standardPoses.count)
            ProgressView(value: doneCount, total: totalCount)
                .tint(EvolvTheme.accent)
                .frame(width: 72)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Ask showcase

    private var askShowcaseView: some View {
        VStack(spacing: 0) {
            HStack {
                Button { finalize() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(EvolvTheme.text)
                        .padding(10)
                        .background(Circle().fill(EvolvTheme.surface))
                        .overlay(Circle().stroke(EvolvTheme.stroke, lineWidth: 1))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(EvolvTheme.accent.opacity(0.10))
                        .frame(width: 180, height: 180)
                        .blur(radius: 24)
                    Image(systemName: "sparkles")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(EvolvTheme.accent)
                }

                VStack(spacing: 12) {
                    Text("Standard scan complete.")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                        .multilineTextAlignment(.center)
                    Text("Want to add showcase poses?\nFlexed comparisons make transformations more visible.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 14) {
                showcasePickerGrid

                EvolvPrimaryButton(
                    title: showcaseQueue.isEmpty ? "Skip — finish scan" : "Continue with \(showcaseQueue.count) showcase pose\(showcaseQueue.count == 1 ? "" : "s")",
                    icon: showcaseQueue.isEmpty ? "checkmark" : "arrow.right"
                ) {
                    if showcaseQueue.isEmpty {
                        finalize()
                    } else {
                        phase = .showcase
                        showcaseIndex = 0
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private var showcasePickerGrid: some View {
        VStack(spacing: 8) {
            ForEach(Pose.showcase) { pose in
                let isSelected = showcaseQueue.contains(pose)
                Button {
                    if isSelected { showcaseQueue.removeAll { $0 == pose } }
                    else { showcaseQueue.append(pose) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(isSelected ? EvolvTheme.accent : EvolvTheme.textFaint)
                        Text(pose.label)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(EvolvTheme.surface)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isSelected ? EvolvTheme.accent.opacity(0.55) : EvolvTheme.stroke, lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Capture handling

    private func handleCaptured(image: UIImage) {
        guard let pose = resolvedCurrentPose else {
            isAnalyzing = false
            return
        }
        isAnalyzing = true
        Task {
            let quality = await QualityGateEngine.evaluate(image: image, expectedPose: pose)
            await MainActor.run {
                isAnalyzing = false
                switch quality.verdict {
                case .pass:
                    commitCapture(image: image, pose: pose)
                case .warning(let issues), .rejected(let issues):
                    pendingImage = image
                    pendingPose = pose
                    qualityIssues = issues
                    showQualityAlert = true
                }
            }
        }
    }

    private var resolvedCurrentPose: Pose? {
        switch phase {
        case .standard: return poseIndex < standardPoses.count ? standardPoses[poseIndex] : nil
        case .showcase: return showcaseIndex < showcaseQueue.count ? showcaseQueue[showcaseIndex] : nil
        default: return nil
        }
    }

    private func commitCapture(image: UIImage, pose: Pose) {
        guard let filename = PhotoStore.save(image) else {
            loadError = "Couldn't save photo to this device. Check your storage and try again."
            showLoadError = true
            return
        }
        let analysis = PhotoStore.analyze(image)
        captures.append(PoseCapture(
            pose: pose,
            imageFilename: filename,
            avgBrightness: analysis.brightness,
            aspectRatio: analysis.aspect
        ))
        withAnimation(.easeInOut(duration: 0.2)) { justCapturedPose = pose }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.easeInOut(duration: 0.2)) { justCapturedPose = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { advance() }
        }
    }

    private var analyzingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(EvolvTheme.accent)
                    .scaleEffect(1.3)
                Text("Checking photo quality…")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
            }
            .padding(28)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(EvolvTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(EvolvTheme.stroke, lineWidth: 1))
            }
        }
    }

    private var captureSuccessFlash: some View {
        ZStack {
            EvolvTheme.accent.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(EvolvTheme.accent)
                Text("Photo saved")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.accent)
            }
        }
        .allowsHitTesting(false)
    }

    private func skipShowcase() {
        if showcaseIndex < showcaseQueue.count - 1 {
            showcaseIndex += 1
        } else {
            finalize()
        }
    }

    private func advance() {
        switch phase {
        case .standard:
            if poseIndex < standardPoses.count - 1 {
                poseIndex += 1
            } else {
                phase = .askShowcase
            }
        case .showcase:
            if showcaseIndex < showcaseQueue.count - 1 {
                showcaseIndex += 1
            } else {
                finalize()
            }
        default: break
        }
    }

    private func finalize() {
        phase = .finalizing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Require at least one standard capture to count as a scan
            let standardCount = captures.filter { $0.pose.category == .standard }.count
            if standardCount > 0 {
                app.addScan(captures: captures)
            }
            phase = .result
        }
    }
}

// MARK: - Capture result

struct CaptureResultView: View {
    @Environment(AppState.self) private var app
    let onDone: () -> Void

    @State private var preWorkout: Bool = false
    @State private var fasted: Bool = false
    @State private var wellHydrated: Bool = false

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 22) {
                    Spacer().frame(height: 16)
                    ZStack {
                        Circle().fill(EvolvTheme.accent.opacity(0.18)).frame(width: 130, height: 130).blur(radius: 20)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(EvolvTheme.accent)
                    }

                    VStack(spacing: 8) {
                        Text("Scan complete")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                        if let last = app.latestScan {
                            let conf: Confidence = last.consistencyScore > 78 ? .high : (last.consistencyScore > 55 ? .medium : .low)
                            ConfidenceChip(confidence: conf)
                        }
                    }

                    if let last = app.latestScan {
                        // Pose thumbnails
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CAPTURED")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .tracking(1.4)
                                .foregroundStyle(EvolvTheme.textFaint)
                                .padding(.horizontal, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(last.captures) { c in
                                        captureThumb(c)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        GlassCard {
                            VStack(spacing: 14) {
                                HStack(spacing: 18) {
                                    consistencyStat("Consistency", value: last.consistencyScore)
                                    Divider().frame(height: 32).overlay(EvolvTheme.stroke)
                                    consistencyStat("Lighting", value: last.lightingScore)
                                    Divider().frame(height: 32).overlay(EvolvTheme.stroke)
                                    consistencyStat("Framing", value: last.framingScore)
                                }
                                Divider().overlay(EvolvTheme.stroke)
                                Text(honestNote(for: last))
                                    .font(.system(size: 13.5, design: .rounded))
                                    .foregroundStyle(EvolvTheme.textMuted)
                                    .lineSpacing(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer().frame(height: 8)

                    // Context chips — optional scan tagging
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SCAN CONDITIONS (OPTIONAL)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(EvolvTheme.textFaint)
                            .padding(.horizontal, 4)
                        HStack(spacing: 10) {
                            contextChip(label: "Pre-workout", icon: "bolt.fill", isOn: $preWorkout)
                            contextChip(label: "Fasted", icon: "moon.fill", isOn: $fasted)
                            contextChip(label: "Well hydrated", icon: "drop.fill", isOn: $wellHydrated)
                        }
                        Text("Tagging conditions helps calibrate interpretation of size fluctuations.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(EvolvTheme.textFaint)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 20)

                    EvolvPrimaryButton(title: "Done", icon: "checkmark") {
                        if preWorkout || fasted || wellHydrated {
                            app.updateLatestScanContext(
                                preWorkout: preWorkout ? true : nil,
                                fasted: fasted ? true : nil,
                                hydration: wellHydrated ? .high : nil
                            )
                        }
                        onDone()
                    }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                }
            }
        }
    }

    private func captureThumb(_ c: PoseCapture) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let img = PhotoStore.loadImage(named: c.imageFilename) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(EvolvTheme.surface)
                    .frame(width: 96, height: 128)
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(width: 96, height: 128)
            Text(c.pose.shortLabel.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(EvolvTheme.stroke, lineWidth: 1))
    }

    private func consistencyStat(_ label: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(EvolvTheme.textFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private func contextChip(label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isOn.wrappedValue ? EvolvTheme.accent : EvolvTheme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(isOn.wrappedValue ? EvolvTheme.accentDim : EvolvTheme.surface)
                    .overlay(Capsule().stroke(isOn.wrappedValue ? EvolvTheme.accent.opacity(0.5) : EvolvTheme.stroke, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
    }

    private func honestNote(for scan: Scan) -> String {
        if scan.lightingScore < 60 {
            return "Lighting differs significantly from your previous scans. Confidence reduced — try to match prior lighting next time."
        }
        if scan.consistencyScore < 65 {
            return "Scan conditions drifted from your baseline. Trends may be less reliable until consistency improves."
        }
        if scan.id == app.firstScan?.id {
            return "Baseline scan saved. Future scans will be compared against this one."
        }
        return "Scan conditions matched your baseline well. This scan will count fully toward your trend analysis."
    }
}

// MARK: - Silhouette shape

private struct SilhouetteShape: Shape {
    let pose: Pose
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.addEllipse(in: CGRect(x: w * 0.38, y: 0, width: w * 0.24, height: w * 0.24))
        let neckY = w * 0.24
        // Variant per pose
        let isSide = (pose == .side || pose == .sideChest)
        let flexed = (pose == .frontDoubleBicep || pose == .backDoubleBicep || pose == .mostMuscular)
        let shoulderSpread: CGFloat = isSide ? 0.16 : (flexed ? 0.56 : 0.40)
        let waistSpread: CGFloat = isSide ? 0.14 : 0.24
        let hipSpread: CGFloat = isSide ? 0.16 : 0.30

        let cx = w / 2
        let shL = cx - w * shoulderSpread / 2
        let shR = cx + w * shoulderSpread / 2
        let wL = cx - w * waistSpread / 2
        let wR = cx + w * waistSpread / 2
        let hL = cx - w * hipSpread / 2
        let hR = cx + w * hipSpread / 2

        p.move(to: CGPoint(x: shL, y: neckY + 4))
        p.addQuadCurve(to: CGPoint(x: wL, y: h * 0.55),
                       control: CGPoint(x: shL - 6, y: h * 0.35))
        p.addQuadCurve(to: CGPoint(x: hL, y: h * 0.70),
                       control: CGPoint(x: wL - 4, y: h * 0.62))
        p.addLine(to: CGPoint(x: cx - w * 0.06, y: h))
        p.addLine(to: CGPoint(x: cx + w * 0.06, y: h))
        p.addLine(to: CGPoint(x: hR, y: h * 0.70))
        p.addQuadCurve(to: CGPoint(x: wR, y: h * 0.55),
                       control: CGPoint(x: wR + 4, y: h * 0.62))
        p.addQuadCurve(to: CGPoint(x: shR, y: neckY + 4),
                       control: CGPoint(x: shR + 6, y: h * 0.35))

        // Flexed arms — sketch bicep curves
        if flexed {
            p.move(to: CGPoint(x: shL - 4, y: h * 0.22))
            p.addQuadCurve(to: CGPoint(x: shL - w * 0.18, y: h * 0.45),
                           control: CGPoint(x: shL - w * 0.22, y: h * 0.30))
            p.addQuadCurve(to: CGPoint(x: shL - w * 0.04, y: h * 0.55),
                           control: CGPoint(x: shL - w * 0.04, y: h * 0.48))
            p.move(to: CGPoint(x: shR + 4, y: h * 0.22))
            p.addQuadCurve(to: CGPoint(x: shR + w * 0.18, y: h * 0.45),
                           control: CGPoint(x: shR + w * 0.22, y: h * 0.30))
            p.addQuadCurve(to: CGPoint(x: shR + w * 0.04, y: h * 0.55),
                           control: CGPoint(x: shR + w * 0.04, y: h * 0.48))
        }
        return p
    }
}

// MARK: - Photo / camera pickers

/// UIImagePickerController for camera capture (camera doesn't have a native SwiftUI equivalent yet).
struct ImagePickerSheet: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        // Fall back to library if camera unavailable (simulator).
        if sourceType == .camera, !UIImagePickerController.isSourceTypeAvailable(.camera) {
            vc.sourceType = .photoLibrary
        } else {
            vc.sourceType = sourceType
        }
        vc.allowsEditing = false
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let img = info[.originalImage] as? UIImage { onPicked(img) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview { CaptureLaunchView().environment(AppState()) }
