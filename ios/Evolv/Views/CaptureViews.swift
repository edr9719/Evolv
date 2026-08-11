import SwiftUI
import PhotosUI
import UIKit

// MARK: - Capture launch (tab entry)

struct CaptureLaunchView: View {
    @State private var captureRequest: CaptureRequest? = nil
    @State private var showStartOptions = false
    @State private var detailRequest: ScanDetailRequest? = nil
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
                            Text(capturePageTitle)
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
                                    HStack(spacing: 12) {
                                        Image(systemName: last.analysisAvailability == .comparable ? "checkmark.circle.fill" : "viewfinder.circle")
                                            .font(.system(size: 22, weight: .light))
                                            .foregroundStyle(EvolvTheme.accent)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(last.analysisAvailability?.label ?? "Legacy scan")
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundStyle(EvolvTheme.text)
                                            Text(lastScanGuidance(last))
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundStyle(EvolvTheme.textMuted)
                                        }
                                    }
                                    Text("Match the same room, lighting, phone height, and distance.")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(EvolvTheme.textMuted)
                                }
                            }
                        }

                        EvolvPrimaryButton(title: captureButtonTitle, icon: "camera.fill") {
                            beginCaptureDecision()
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

    private var captureButtonTitle: String {
        guard let today = app.todayCanonicalScan else {
            return app.hasAnyScans ? "Start guided capture" : "Capture baseline"
        }
        return today.recommendedRepairPoses.isEmpty ? "Today's scan options" : "Improve today's scan"
    }

    private var capturePageTitle: String {
        if app.todayCanonicalScan != nil { return "Today's scan is saved" }
        return app.hasAnyScans ? "Capture your next scan" : "Capture your baseline"
    }

    private func lastScanGuidance(_ scan: Scan) -> String {
        if !scan.recommendedRepairPoses.isEmpty {
            return "The photos are saved; review only the automatic checks that were unavailable."
        }
        if scan.analysisAvailability == .baselineOnly {
            return "Your next complete scan creates the first comparison."
        }
        return "Repeat the same upper-body crop and relaxed poses."
    }

    private func beginCaptureDecision() {
        if app.todayCanonicalScan == nil {
            captureRequest = .newCanonical
        } else {
            showStartOptions = true
        }
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

    let scanRole: ScanRole
    let repairScanID: UUID?
    let repairPoses: [Pose]?
    let validationContext: ValidationCaptureContext?
    let onValidationSetSaved: ((UUID) -> Void)?

    init(
        scanRole: ScanRole = .canonical,
        repairScanID: UUID? = nil,
        repairPoses: [Pose]? = nil,
        validationContext: ValidationCaptureContext? = nil,
        onValidationSetSaved: ((UUID) -> Void)? = nil
    ) {
        self.scanRole = scanRole
        self.repairScanID = repairScanID
        self.repairPoses = repairPoses
        self.validationContext = validationContext
        self.onValidationSetSaved = onValidationSetSaved
        let initialCaptures = validationContext?.initialCaptures ?? []
        _captures = State(initialValue: initialCaptures)
        let completedPoses = Set(initialCaptures.map(\.pose))
        _poseIndex = State(initialValue: Pose.required.firstIndex(where: { !completedPoses.contains($0) }) ?? 0)
        _phase = State(initialValue: validationContext != nil && completedPoses == Set(Pose.required)
            ? .finalizing
            : .standard)
        _sessionCameraPosition = State(initialValue: validationContext?.lockedCameraPosition)
    }

    enum Phase: Equatable { case standard, review, askShowcase, showcase, finalizing, result }

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
    @State private var sessionCameraPosition: CaptureCameraPosition? = nil

    // Photo review and conservative quality assessment
    @State private var pendingImage: UIImage? = nil
    @State private var pendingPose: Pose? = nil
    @State private var pendingSource: CaptureSource? = nil
    @State private var pendingPixelSize: NormalizedPixelSize? = nil
    @State private var pendingCameraMetadata: CaptureCameraMetadata? = nil
    @State private var pendingAssessment: CaptureAssessment? = nil
    @State private var assessmentToken: UUID? = nil
    @State private var isAnalyzing: Bool = false
    @State private var isSaving: Bool = false
    @State private var loadError: String? = nil
    @State private var showLoadError: Bool = false

    // UX state
    @State private var showCancelConfirmation: Bool = false
    @State private var justCapturedPose: Pose? = nil
    @State private var resultScanID: UUID? = nil

    private var standardPoses: [Pose] {
        let requested = repairPoses ?? Pose.required
        return requested.isEmpty ? Pose.required : Pose.required.filter(requested.contains)
    }
    private var isRepairing: Bool { repairScanID != nil }
    private var isValidationCapture: Bool { validationContext != nil }

    var body: some View {
        ZStack {
            AmbientBackground()
            content
                .animation(.easeInOut(duration: 0.3), value: phase)
                .animation(.easeInOut(duration: 0.3), value: poseIndex)
                .animation(.easeInOut(duration: 0.3), value: showcaseIndex)

            if isAnalyzing && phase != .review {
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
        .onAppear {
            // A force-quit can occur after the third photo was checkpointed
            // but before the set record was committed. Resume by committing
            // that complete draft instead of asking for a duplicate pose.
            if isValidationCapture,
               phase == .finalizing,
               resultScanID == nil {
                finalize()
            }
        }
        .fullScreenCover(isPresented: $showCameraSheet) {
            if let pose = resolvedCurrentPose {
                TimerCameraView(
                    pose: pose,
                    previousPhoto: previousImage(for: pose),
                    preferredPosition: validationContext?.lockedCameraPosition
                        ?? sessionCameraPosition
                        ?? previousCapture(for: pose)?.cameraMetadata?.position,
                    allowsCameraSwitch: !isValidationCapture
                ) { result in
                    handleCaptured(
                        image: result.image,
                        source: .camera,
                        cameraMetadata: result.metadata
                    )
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
                            handleCaptured(image: img, source: .photoLibrary, cameraMetadata: nil)
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
        .alert("Couldn't use photo", isPresented: $showLoadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadError ?? "Try a different photo.")
        }
        .alert(isValidationCapture ? "Discard current set draft?" : "Discard scan?", isPresented: $showCancelConfirmation) {
            if isValidationCapture {
                Button("Save draft and exit") { leaveValidationDraft() }
                Button("Discard set draft", role: .destructive) { discardSession() }
            } else {
                Button(isRepairing ? "Discard replacements" : "Discard", role: .destructive) {
                    discardSession()
                }
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            let count = captures.count
            Text(isValidationCapture
                 ? "Save the \(count) captured photo\(count == 1 ? "" : "s") and resume this set later, or discard only this set's draft. Earlier completed sets stay saved."
                 : (isRepairing
                    ? "Your original scan will remain unchanged. The \(count) new photo\(count == 1 ? "" : "s") will be deleted."
                    : "You've captured \(count) pose\(count == 1 ? "" : "s"). Discarding will delete this session."))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .standard:
            posePromptView(
                pose: standardPoses[poseIndex],
                stepLabel: validationContext.map {
                    "CONSISTENCY SET \($0.setNumber) OF \(ValidationStudySession.requiredSetCount)"
                } ?? "POSE \(poseIndex + 1) OF \(standardPoses.count)",
                isShowcase: false,
                isLastInPhase: poseIndex == standardPoses.count - 1
            )
        case .review:
            captureReviewView
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
            if let resultScanID {
                CaptureResultView(
                    scanID: resultScanID,
                    wasRepair: isRepairing,
                    onDone: { dismiss() }
                )
            }
        }
    }

    // MARK: - Pose prompt

    private func posePromptView(pose: Pose, stepLabel: String, isShowcase: Bool, isLastInPhase: Bool) -> some View {
        VStack(spacing: 0) {
            topBar(stepLabel: stepLabel, pose: pose)

            Spacer(minLength: 8)

            PoseReferenceCard(
                pose: pose,
                hasPreviousPhoto: previousImage(for: pose) != nil
            )
            .frame(maxWidth: .infinity)
            .frame(height: 410)
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
                Text("Match the position and crop—not the example person's body shape.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                if let cameraGuidance = cameraGuidance(for: pose) {
                    Label(
                        cameraGuidance,
                        systemImage: "camera.rotate"
                    )
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.accent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                }
            }
            .padding(.top, standardCaptures.isEmpty ? 18 : 10)

            Spacer()

            VStack(spacing: 12) {
                EvolvPrimaryButton(title: "Take photo", icon: "camera.fill") {
                    showCameraSheet = true
                }
                if !isValidationCapture {
                    Button { showLibraryPicker = true } label: {
                        Text("Choose from library")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }

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

    // MARK: - Photo review

    private var captureReviewView: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if captures.isEmpty {
                        clearPendingReview()
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
                    Text("REVIEW PHOTO")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(EvolvTheme.accent)
                    Text(pendingPose?.label ?? "Photo")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 16) {
                    if let image = pendingImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 470)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(EvolvTheme.stroke, lineWidth: 1)
                            }
                    }

                    assessmentCard

                    reviewChecklistCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 12) {
                EvolvPrimaryButton(
                    title: usePhotoButtonTitle,
                    icon: isSaving ? nil : "checkmark",
                    enabled: !isAnalyzing && !isSaving && pendingAssessment != nil
                ) {
                    Task { await commitPendingCapture() }
                }

                Button {
                    retakePendingPhoto()
                } label: {
                    Text("Retake")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private var reviewChecklistCard: some View {
        let pose = pendingPose ?? .front
        let hasPrevious = previousImage(for: pose) != nil
        return VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CHECK IT YOURSELF")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(EvolvTheme.accent)
                Text("Automatic checks cannot confirm every detail.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
            }

            ForEach(pose.reviewChecklist(matchingPrevious: hasPrevious), id: \.self) { item in
                HStack(spacing: 10) {
                    Image(systemName: "circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EvolvTheme.accent)
                    Text(item)
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(EvolvTheme.stroke, lineWidth: 1))
        }
    }

    private var assessmentCard: some View {
        HStack(alignment: .top, spacing: 12) {
            if isAnalyzing {
                ProgressView()
                    .tint(EvolvTheme.accent)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: assessmentIcon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(assessmentColor)
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(isAnalyzing ? "Checking photo…" : (pendingAssessment?.automaticStatusTitle ?? "Automatic check unavailable"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Text(isAnalyzing ? "This usually takes a moment." : assessmentMessage)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(EvolvTheme.stroke, lineWidth: 1))
        }
    }

    private var assessmentIcon: String {
        switch pendingAssessment?.status {
        case .ready: return "checkmark.circle.fill"
        case .reviewRecommended: return "exclamationmark.triangle.fill"
        case .unavailable, .none: return "eye.circle"
        }
    }

    private var assessmentColor: Color {
        switch pendingAssessment?.status {
        case .ready: return EvolvTheme.accent
        case .reviewRecommended: return EvolvTheme.stable
        case .unavailable, .none: return EvolvTheme.textMuted
        }
    }

    private var assessmentMessage: String {
        guard let assessment = pendingAssessment else {
            return "Review the photo yourself before continuing."
        }
        switch assessment.status {
        case .ready:
            return "Required torso framing was verified. Check the pose yourself; any unsupported region will be excluded from analysis."
        case .reviewRecommended:
            if assessment.confirmedIssues.contains(.tooDark) {
                return "The photo is extremely dark, which can hide body contours. Retaking in more light is recommended."
            }
            if assessment.confirmedIssues.contains(.overexposed) {
                return "The photo is heavily overexposed, which can erase body contours. Softer lighting is recommended."
            }
            return "A specific image issue may limit analysis. Review it carefully before continuing."
        case .unavailable:
            return "Evolv couldn't verify the framing automatically. This does not mean the photo is poor—review it and use it if your upper body is clear."
        }
    }

    private var usePhotoButtonTitle: String {
        if isSaving { return "Saving photo…" }
        return pendingAssessment?.status == .reviewRecommended ? "Use Photo Anyway" : "Use Photo"
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

    private func handleCaptured(
        image: UIImage,
        source: CaptureSource,
        cameraMetadata: CaptureCameraMetadata?
    ) {
        guard let pose = resolvedCurrentPose else {
            isAnalyzing = false
            return
        }
        let prepared = PhotoStore.prepare(image)
        let token = UUID()
        pendingImage = prepared.image
        pendingPose = pose
        pendingSource = source
        pendingPixelSize = prepared.pixelSize
        pendingCameraMetadata = cameraMetadata
        if let cameraPosition = cameraMetadata?.position {
            sessionCameraPosition = cameraPosition
        }
        pendingAssessment = nil
        assessmentToken = token
        phase = .review
        isAnalyzing = true
        Task {
            let assessment = await QualityGateEngine.assessWithTimeout(
                image: prepared.image,
                expectedPose: pose,
                seconds: 5
            )
            await MainActor.run {
                guard assessmentToken == token else { return }
                pendingAssessment = assessment
                isAnalyzing = false
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

    /// The ghost overlay is always loaded from Evolv's on-device photo store.
    /// Repairs use the photo being replaced; new scans use the canonical
    /// baseline because the analysis compares against that same reference.
    /// No reference photo leaves the device.
    private func previousCapture(for pose: Pose) -> PoseCapture? {
        let referenceScan: Scan?
        if let anchorScanID = validationContext?.anchorScanID {
            referenceScan = app.scan(id: anchorScanID)
        } else if let repairScanID {
            referenceScan = app.scan(id: repairScanID)
        } else {
            referenceScan = app.firstScan
        }
        return referenceScan?.capture(for: pose)
    }

    private func previousImage(for pose: Pose) -> UIImage? {
        guard let filename = previousCapture(for: pose)?.imageFilename else { return nil }
        return PhotoStore.loadImage(named: filename)
    }

    private func cameraGuidance(for pose: Pose) -> String? {
        if let validationContext {
            return "Using \(validationContext.lockedCameraPosition.label) camera for all five sets."
        }
        guard let referencePosition = previousCapture(for: pose)?.cameraMetadata?.position else {
            return nil
        }
        let openingPosition = sessionCameraPosition ?? referencePosition
        if openingPosition == referencePosition {
            return "Camera opens on \(referencePosition.label) to match your reference photo."
        }
        return "This reference used \(referencePosition.label). Switch to \(referencePosition.label) for the closest comparison."
    }

    private func commitPendingCapture() async {
        guard let image = pendingImage,
              let pose = pendingPose,
              let source = pendingSource,
              let pixelSize = pendingPixelSize,
              var assessment = pendingAssessment else { return }

        isSaving = true
        if assessment.status == .reviewRecommended {
            assessment.userOverrodeRecommendation = true
        }

        do {
            let filename = try await PhotoStore.save(image)
            let analysis = PhotoStore.analyze(image)
            let capture = PoseCapture(
                pose: pose,
                imageFilename: filename,
                avgBrightness: analysis.brightness,
                aspectRatio: analysis.aspect,
                captureSource: source,
                assessment: assessment,
                normalizedPixelSize: pixelSize,
                cameraMetadata: pendingCameraMetadata
            )
            captures.append(capture)
            if let validationContext {
                do {
                    try app.updateValidationDraft(
                        sessionID: validationContext.sessionID,
                        setNumber: validationContext.setNumber,
                        captures: captures
                    )
                } catch {
                    captures.removeAll { $0.id == capture.id }
                    PhotoStore.delete(named: filename)
                    throw error
                }
            }
            isSaving = false
            clearPendingReview()
            phase = pose.category == .standard ? .standard : .showcase
            withAnimation(.easeInOut(duration: 0.2)) { justCapturedPose = pose }
            try? await Task.sleep(nanoseconds: 750_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { justCapturedPose = nil }
            try? await Task.sleep(nanoseconds: 150_000_000)
            advance()
        } catch {
            isSaving = false
            loadError = error.localizedDescription
            showLoadError = true
        }
    }

    private func retakePendingPhoto() {
        let pose = pendingPose
        clearPendingReview()
        phase = pose?.category == .showcase ? .showcase : .standard
    }

    private func clearPendingReview() {
        assessmentToken = nil
        pendingImage = nil
        pendingPose = nil
        pendingSource = nil
        pendingPixelSize = nil
        pendingCameraMetadata = nil
        pendingAssessment = nil
        isAnalyzing = false
    }

    private func discardSession() {
        if let validationContext {
            app.discardValidationDraft(sessionID: validationContext.sessionID)
        } else {
            PhotoStore.delete(named: captures.map(\.imageFilename))
        }
        captures.removeAll()
        clearPendingReview()
        dismiss()
    }

    private func leaveValidationDraft() {
        // Each accepted capture was already checkpointed by
        // updateValidationDraft. A photo still on the review screen has not
        // been persisted and is intentionally dropped when leaving.
        clearPendingReview()
        dismiss()
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
            } else if isRepairing || isValidationCapture {
                finalize()
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
        let capturedStandard = Set(captures.filter { $0.pose.category == .standard }.map(\.pose))
        let requiredForSession = isRepairing ? Set(standardPoses) : Set(Pose.required)
        guard requiredForSession.isSubset(of: capturedStandard) else {
            if let missingPose = standardPoses.first(where: { !capturedStandard.contains($0) }),
               let missing = standardPoses.firstIndex(of: missingPose) {
                poseIndex = missing
            }
            phase = .standard
            loadError = isRepairing
                ? "Capture every selected replacement before updating this scan."
                : "Front, side, and back relaxed photos are all required before the scan can be saved."
            showLoadError = true
            return
        }
        phase = .finalizing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            do {
                if let repairScanID {
                    let updated = try app.replaceCaptures(in: repairScanID, with: captures)
                    resultScanID = updated.id
                } else if let validationContext {
                    let savedID = try app.addValidationSet(
                        sessionID: validationContext.sessionID,
                        setNumber: validationContext.setNumber,
                        captures: captures
                    )
                    resultScanID = savedID
                    onValidationSetSaved?(savedID)
                    dismiss()
                    return
                } else {
                    resultScanID = try app.addScan(captures: captures, role: scanRole)
                }
                phase = .result
            } catch {
                if !isValidationCapture {
                    PhotoStore.delete(named: captures.map(\.imageFilename))
                    captures.removeAll()
                    poseIndex = 0
                }
                phase = .standard
                loadError = error.localizedDescription
                showLoadError = true
            }
        }
    }
}

// MARK: - Capture result

struct CaptureResultView: View {
    @Environment(AppState.self) private var app
    let scanID: UUID
    let wasRepair: Bool
    let onDone: () -> Void

    @State private var preWorkout: Bool = false
    @State private var fasted: Bool = false
    @State private var wellHydrated: Bool = false
    @State private var showRepairPicker = false
    @State private var repairRequest: CaptureRequest? = nil

    private var scan: Scan? { app.scan(id: scanID) }

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
                        Text(resultTitle)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                        if let last = scan {
                            Text(last.analysisAvailability?.label ?? "Saved")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(EvolvTheme.textMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().stroke(EvolvTheme.stroke, lineWidth: 1))
                        }
                    }

                    if let last = scan {
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
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(Pose.required) { pose in
                                    if let capture = last.capture(for: pose) {
                                        HStack(alignment: .top, spacing: 11) {
                                            Image(systemName: resultStatusIcon(capture.assessment?.status))
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(resultStatusColor(capture.assessment?.status))
                                                .frame(width: 22)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(pose.label)
                                                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(EvolvTheme.text)
                                                Text(capture.assessment?.automaticStatusTitle ?? "Automatic check unavailable")
                                                    .font(.system(size: 11.5, design: .rounded))
                                                    .foregroundStyle(EvolvTheme.textMuted)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                    }
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
                    if !wasRepair {
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
                    }

                    if let scan, !scan.recommendedRepairPoses.isEmpty {
                        Button {
                            showRepairPicker = true
                        } label: {
                            Text("Improve verification for \(scan.recommendedRepairPoses.count) photo\(scan.recommendedRepairPoses.count == 1 ? "" : "s")")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(EvolvTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    EvolvPrimaryButton(title: "Done", icon: "checkmark") {
                        if preWorkout || fasted || wellHydrated {
                            app.updateScanContext(
                                scanID: scanID,
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
    }

    private var resultTitle: String {
        guard let scan else { return wasRepair ? "Scan improved" : "Scan complete" }
        if wasRepair { return "Scan improved" }
        if scan.resolvedRole == .sameDayExtra { return "Extra scan saved" }
        return app.firstScan?.id == scan.id ? "Baseline saved" : "Scan complete"
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

    private func resultStatusIcon(_ status: CaptureVerificationStatus?) -> String {
        switch status {
        case .ready: return "checkmark.circle.fill"
        case .reviewRecommended: return "exclamationmark.triangle.fill"
        case .unavailable, .none: return "eye.slash"
        }
    }

    private func resultStatusColor(_ status: CaptureVerificationStatus?) -> Color {
        switch status {
        case .ready: return EvolvTheme.accent
        case .reviewRecommended: return EvolvTheme.stable
        case .unavailable, .none: return EvolvTheme.textMuted
        }
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
        switch scan.analysisAvailability {
        case .baselineOnly:
            return "Baseline saved. Progress requires another complete, comparable upper-body scan."
        case .comparable:
            return "At least one upper-body region has supported comparison evidence. Other regions remain unavailable unless their evidence is also supported."
        case .partialEvidence:
            let poses = scan.recommendedRepairPoses.map(\.shortLabel).joined(separator: ", ")
            return poses.isEmpty
                ? "Scan saved. Unsupported regions will be marked unavailable, not guessed."
                : "Baseline saved. Automatic checks were unavailable for \(poses). This does not mean those photos are poor."
        case .processingFailed:
            return "The photos are saved, but automatic analysis was unavailable. No progress claim will be generated from missing evidence."
        case .documentationOnly:
            return "This same-day extra is saved for your timeline and will not influence progress trends."
        case .validationOnly:
            return "This consistency-test set stays on this iPhone and will not influence progress trends."
        case .none:
            return "Legacy scan saved. Evolv will not treat its unverified capture scores as current evidence."
        }
    }
}

// MARK: - Pose reference

private struct PoseReferenceCard: View {
    let pose: Pose
    let hasPreviousPhoto: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(pose.referenceAssetName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.02), .black.opacity(0.08), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 9) {
                if hasPreviousPhoto {
                    Label("Previous photo available in camera", systemImage: "square.stack.3d.up.fill")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                }
                HStack(spacing: 12) {
                    guidanceItem(icon: "viewfinder", text: pose.referenceFramingText)
                    guidanceItem(icon: "iphone", text: pose.cameraHeightText)
                }
                guidanceItem(icon: "sun.max.fill", text: "Soft light from the front · stand away from the wall")
            }
            .padding(16)
        }
        .overlay(alignment: .topLeading) {
            Text("POSE EXAMPLE · NOT A TARGET")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(.black.opacity(0.62)))
                .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(EvolvTheme.stroke, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example for \(pose.label). Match the pose and framing, not the person's body shape.")
    }

    private func guidanceItem(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(2)
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
