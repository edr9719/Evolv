import SwiftUI
import UIKit

struct PilotEnrollmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = PilotSubmissionCoordinator.shared
    @State private var step: Step = .explanation
    @State private var inviteCode = ""
    @State private var shareScope: PilotShareScope = .resultsOnly
    @State private var adultConfirmed = false
    @State private var showDetails = false
    @State private var errorMessage: String?
    @State private var validatedInvitation: PilotInvitationValidation?

    let onEnrolled: (() -> Void)?

    init(onEnrolled: (() -> Void)? = nil) {
        self.onEnrolled = onEnrolled
    }

    private enum Step: Int, CaseIterable {
        case explanation
        case consent
        case invite
        case sharing

        var title: String {
            switch self {
            case .explanation: return "About the pilot"
            case .consent: return "Your choice"
            case .invite: return "Invitation"
            case .sharing: return "Sharing choice"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        stepHeader
                        stepContent

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12.5, design: .rounded))
                                .foregroundStyle(EvolvTheme.stalled)
                        }

                        stepAction
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Evolv pilot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .explanation {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            step = Step(rawValue: step.rawValue - 1) ?? .explanation
                            errorMessage = nil
                            if step == .invite { validatedInvitation = nil }
                        }
                        .tint(EvolvTheme.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.tint(EvolvTheme.accent)
                }
            }
        }
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STEP \(step.rawValue + 1) OF \(Step.allCases.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(EvolvTheme.accent)
            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .tint(EvolvTheme.accent)
            Text(step.title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .explanation:
            VStack(alignment: .leading, spacing: 14) {
                Text("Help us check whether Evolv produces consistent results when five photo sets are taken under the same conditions.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(3)
                    .accessibilityIdentifier("pilot.enrollment.explanation")
                enrollmentPoint("The test takes about 20–30 minutes and stays on this iPhone while you complete it.")
                enrollmentPoint("After Set 5, you review the results and decide exactly what—if anything—to share.")
                enrollmentPoint("Nothing uploads automatically. This pilot does not change your personal timeline photos.")
            }
        case .consent:
            VStack(alignment: .leading, spacing: 14) {
                Text("Joining is optional. You can stop sharing later without deleting scans stored on this iPhone.")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(3)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() }
                } label: {
                    HStack {
                        Text("How your data is used")
                        Spacer()
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .padding(16)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(EvolvTheme.surface)
                            .stroke(EvolvTheme.stroke, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)

                if showDetails { dataUseDetails.transition(.opacity.combined(with: .move(edge: .top))) }

                Toggle(isOn: $adultConfirmed) {
                    Text("I am 18 or older and I choose to join this pilot.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                }
                .tint(EvolvTheme.accent)
                .accessibilityIdentifier("pilot.enrollment.adult-consent")
            }

        case .invite:
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter the private invitation code Edgar gave you. It connects this iPhone to a disposable pilot participant record—not your name or Apple ID.")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(3)
                SettingsGroup(header: "Invite code") {
                    TextField("Enter invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(EvolvTheme.text)
                        .padding(16)
                        .accessibilityIdentifier("pilot.enrollment.invite-code")
                }
                Text("Checking the invitation does not use it. It is used only after you review sharing and tap Join pilot.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
                    .lineSpacing(2)
            }

        case .sharing:
            VStack(alignment: .leading, spacing: 12) {
                if let validatedInvitation {
                    Label("Invitation verified for \(validatedInvitation.studyName)", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                        .accessibilityIdentifier("pilot.enrollment.invitation-verified")
                }
                Text("Choose a starting preference. After the test, you can change it before sharing.")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                ForEach(PilotShareScope.allCases) { scope in
                    scopeButton(scope)
                }
                Text("Results-only sends no photos. If you choose photos, you approve them one by one after Set 5 and they are encrypted on this iPhone before upload.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
                    .lineSpacing(2)
            }
            .accessibilityIdentifier("pilot.enrollment.sharing-choice")
        }
    }

    @ViewBuilder
    private var stepAction: some View {
        switch step {
        case .explanation:
            EvolvPrimaryButton(title: "Continue to consent", icon: "arrow.right") {
                step = .consent
            }
            .accessibilityIdentifier("pilot.enrollment.continue")
        case .consent:
            EvolvPrimaryButton(
                title: adultConfirmed ? "Continue to invitation" : "Confirm to continue",
                icon: "arrow.right",
                enabled: adultConfirmed
            ) {
                step = .invite
            }
        case .invite:
            EvolvPrimaryButton(
                title: coordinator.isWorking
                    ? "Checking invitation…"
                    : inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Enter your invite code"
                    : "Continue to sharing choice",
                icon: "arrow.right",
                enabled: !coordinator.isWorking
                    && !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                validateInvitation()
            }
            .accessibilityIdentifier("pilot.enrollment.validate-invitation")
        case .sharing:
            EvolvPrimaryButton(
                title: coordinator.isWorking ? "Joining…" : "Join pilot",
                icon: "checkmark.shield",
                enabled: !coordinator.isWorking
            ) {
                join()
            }
            .accessibilityIdentifier("pilot.enrollment.join")
        }
    }

    private func enrollmentPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(EvolvTheme.accent)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .lineSpacing(2)
        }
    }

    private func scopeButton(_ scope: PilotShareScope) -> some View {
        Button { shareScope = scope } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: shareScope == scope ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(shareScope == scope ? EvolvTheme.accent : EvolvTheme.textFaint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(scope.title)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text(scope.detail)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(2)
                }
                Spacer()
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(EvolvTheme.surface)
                    .stroke(shareScope == scope ? EvolvTheme.accent.opacity(0.7) : EvolvTheme.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var dataUseDetails: some View {
        GlassCard(padding: 17, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                detail("Results include normalized regional features and changes, pose-match and evidence status, conflicts, processing failures, test conditions, app and analysis versions, iPhone model, iOS version, and camera configuration.")
                detail("Results do not include names, email, location, advertising IDs, filenames, raw landmarks or masks, raw height, weight, or tape measurements.")
                detail("If you choose photos, you approve them one by one after the test. They are encrypted on this iPhone before upload.")
                detail("Pilot photos are deleted when the pilot closes. Structured results are deleted 12 months after submission. You can withdraw sooner without deleting your local timeline.")
                detail("Your Evolv Read remains generated on this iPhone during the pilot.")
            }
        }
    }

    private func detail(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(EvolvTheme.accent).frame(width: 4, height: 4).padding(.top, 7)
            Text(text)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .lineSpacing(2)
        }
    }

    private func join() {
        let consent = PilotConsent(
            version: PilotStudyConfiguration.consentVersion,
            adultConfirmed: adultConfirmed,
            shareScope: shareScope,
            acceptedAt: Date()
        )
        Task {
            do {
                try await coordinator.enroll(inviteCode: inviteCode, consent: consent)
                onEnrolled?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func validateInvitation() {
        errorMessage = nil
        Task {
            do {
                validatedInvitation = try await coordinator.validateInvitation(inviteCode)
                step = .sharing
            } catch {
                validatedInvitation = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PilotSubmissionCard: View {
    let session: ValidationStudySession
    let scans: [Scan]

    @State private var coordinator = PilotSubmissionCoordinator.shared
    @State private var scope: PilotShareScope = .resultsOnly
    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var photoApproval = false
    @State private var errorMessage: String?
    @State private var showEnrollment = false

    private var choices: [PilotPhotoChoice] {
        PilotResultsBuilder.photoChoices(session: session, scans: scans)
    }

    private var existing: PilotSubmissionRecord? {
        coordinator.submissions.last { $0.localSessionID == session.id }
    }

    var body: some View {
        GlassCard(padding: 18, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Optional pilot sharing", systemImage: "lock.shield")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)

                if coordinator.enrollment?.status != .active {
                    Text("This completed test remains only on this iPhone. You can still join the invited pilot, then review this test and explicitly choose results only or individual photos.")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(2)
                    EvolvPrimaryButton(
                        title: "Join pilot & review sharing",
                        icon: "checkmark.shield"
                    ) {
                        showEnrollment = true
                    }
                    .accessibilityIdentifier("pilot.retrospective.join")
                    Text("Joining does not upload this test. Sharing requires a separate confirmation after enrollment.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                } else if let existing, existing.status == .completed {
                    Label(existing.selectedPhotos.isEmpty ? "Results shared · no photos" : "Results and \(existing.selectedPhotos.count) selected photos shared", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                    if let receipt = existing.receiptCode {
                        Text("Receipt \(receipt)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(EvolvTheme.textFaint)
                    }
                } else {
                    Picker("Sharing", selection: $scope) {
                        ForEach(PilotShareScope.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if scope == .resultsAndSelectedPhotos {
                        Text("Tap every photo you approve. Unselected photos stay only on this iPhone.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                        photoGrid
                        Toggle("I approve uploading only the selected photos", isOn: $photoApproval)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .tint(EvolvTheme.accent)
                    }

                    if let existing, existing.status == .failed || existing.status == .queued {
                        Label("Encrypted retry package saved on this iPhone", systemImage: "arrow.clockwise.icloud")
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(EvolvTheme.stable)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(EvolvTheme.stalled)
                    }
                    EvolvPrimaryButton(
                        title: coordinator.isWorking ? "Sharing…" : (existing == nil ? "Review and share" : "Retry secure upload"),
                        icon: "lock.shield",
                        enabled: !coordinator.isWorking && (scope == .resultsOnly || (photoApproval && !selectedPhotoIDs.isEmpty))
                    ) {
                        submit()
                    }
                    Text(scope == .resultsOnly ? "No images are included." : "Photos are encrypted before they leave this iPhone.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            scope = coordinator.enrollment?.consent.shareScope ?? .resultsOnly
            if let existing {
                selectedPhotoIDs = Set(existing.selectedPhotos.map(\.captureID))
                photoApproval = !selectedPhotoIDs.isEmpty
            }
        }
        .sheet(isPresented: $showEnrollment) {
            PilotEnrollmentSheet()
        }
    }

    private var photoGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(choices) { choice in
                Button { toggle(choice.id) } label: {
                    ZStack(alignment: .topTrailing) {
                        photo(for: choice)
                            .aspectRatio(0.72, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        Image(systemName: selectedPhotoIDs.contains(choice.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedPhotoIDs.contains(choice.id) ? EvolvTheme.accent : .white)
                            .shadow(radius: 2)
                            .padding(6)
                        Text("\(choice.setNumber) · \(choice.pose.shortLabel)")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set \(choice.setNumber), \(choice.pose.label), \(selectedPhotoIDs.contains(choice.id) ? "selected" : "not selected")")
            }
        }
    }

    @ViewBuilder
    private func photo(for choice: PilotPhotoChoice) -> some View {
        if let scan = scans.first(where: { $0.id == choice.scanID }),
           let capture = scan.captures.first(where: { $0.id == choice.captureID }),
           let image = PhotoStore.loadImage(named: capture.imageFilename) {
            Image(uiImage: image).resizable()
        } else {
            Rectangle().fill(EvolvTheme.surfaceHi)
                .overlay(Image(systemName: "photo").foregroundStyle(EvolvTheme.textFaint))
        }
    }

    private func toggle(_ id: UUID) {
        if selectedPhotoIDs.contains(id) { selectedPhotoIDs.remove(id) }
        else { selectedPhotoIDs.insert(id) }
        photoApproval = false
    }

    private func submit() {
        let consent = PilotConsent(
            version: PilotStudyConfiguration.consentVersion,
            adultConfirmed: true,
            shareScope: scope,
            acceptedAt: Date()
        )
        Task {
            do {
                _ = try await coordinator.prepareAndSubmit(
                    session: session,
                    scans: scans,
                    consent: consent,
                    selectedPhotos: selectedPhotoIDs,
                    photoApprovalConfirmed: photoApproval
                )
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PilotDataSharingView: View {
    @State private var coordinator = PilotSubmissionCoordinator.shared
    @State private var showEnrollment = false
    @State private var confirmWithdrawal = false
    @State private var recoveryCode = ""
    @State private var message: String?

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let enrollment = coordinator.enrollment {
                        GlassCard(padding: 18, cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 9) {
                                Label(enrollment.status == .active ? "Pilot sharing active" : "Pilot sharing ended", systemImage: "checkmark.shield")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(EvolvTheme.text)
                                Text(enrollment.consent.shareScope.title)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(EvolvTheme.accent)
                                Text("Pilot photos delete by \(enrollment.pilotClosesAt.formatted(date: .abbreviated, time: .omitted)). Results delete no later than \(enrollment.resultsDeleteAfter.formatted(date: .abbreviated, time: .omitted)).")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(EvolvTheme.textMuted)
                                    .lineSpacing(2)
                                if let code = coordinator.deletionCode() {
                                    HStack {
                                        Text("Deletion code: \(code)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .textSelection(.enabled)
                                        Spacer()
                                        Button("Copy") { UIPasteboard.general.string = code }
                                            .font(.system(size: 11, weight: .semibold))
                                            .tint(EvolvTheme.accent)
                                    }
                                }
                            }
                        }
                        if enrollment.status == .active {
                            PilotOngoingContributionCard()

                            Button(role: .destructive) { confirmWithdrawal = true } label: {
                                Label("Delete my shared pilot data", systemImage: "trash")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                            }
                            .buttonStyle(.bordered)
                            .tint(EvolvTheme.stalled)
                        }
                    } else {
                        Text("Pilot sharing is optional and invite-only. Normal scans stay on this iPhone unless you explicitly approve a pilot submission.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                            .lineSpacing(3)
                        EvolvPrimaryButton(title: "Join with an invite", icon: "ticket") { showEnrollment = true }
                    }

                    SettingsGroup(
                        header: "Delete after reinstall",
                        footer: "Use the recovery/deletion code you received when joining. This deletes shared server data only; it does not change this iPhone's timeline."
                    ) {
                        VStack(spacing: 10) {
                            TextField("Deletion code", text: $recoveryCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(size: 14, design: .monospaced))
                                .padding(14)
                            Button("Delete shared data with code") { deleteWithCode() }
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(EvolvTheme.stalled)
                                .disabled(recoveryCode.isEmpty || coordinator.isWorking)
                                .padding(.bottom, 14)
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Pilot data sharing")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEnrollment) { PilotEnrollmentSheet() }
        .alert("Delete shared pilot data?", isPresented: $confirmWithdrawal) {
            Button("Cancel", role: .cancel) {}
            Button("Delete shared data", role: .destructive) { withdraw() }
        } message: {
            Text("Evolv will delete uploaded pilot results and photos. Your local scans and timeline will remain on this iPhone.")
        }
    }

    private func withdraw() {
        Task {
            do { try await coordinator.withdraw(); message = coordinator.lastMessage }
            catch { message = error.localizedDescription }
        }
    }

    private func deleteWithCode() {
        Task {
            do { try await coordinator.deleteWithRecoveryCode(recoveryCode); message = coordinator.lastMessage; recoveryCode = "" }
            catch { message = error.localizedDescription }
        }
    }
}

struct PilotOngoingContributionCard: View {
    @State private var coordinator = PilotSubmissionCoordinator.shared
    @State private var pendingMode: PilotOngoingContributionMode?
    @State private var confirmDisable = false
    @State private var message: String?

    var body: some View {
        GlassCard(padding: 18, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Future progress scans", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)

                if !coordinator.hasCompletedConsistencySubmission {
                    Text("First share the completed five-set consistency test. Future contribution is a separate choice and never uploads earlier timeline scans.")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(2)
                } else if let mode = coordinator.ongoingMode {
                    Text(mode.title)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                    Text(mode.detail)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(2)
                    HStack(spacing: 10) {
                        Button("Change") {
                            pendingMode = mode == .resultsOnly ? .askEveryScan : .resultsOnly
                        }
                        .buttonStyle(.bordered)
                        .tint(EvolvTheme.accent)
                        Button("Turn off", role: .destructive) { confirmDisable = true }
                            .buttonStyle(.bordered)
                            .tint(EvolvTheme.stalled)
                    }
                } else {
                    Text("Optional. Choose how future canonical progress scans may help after their on-device analysis. Earlier scans and same-day extras are never included.")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(2)
                    ForEach(PilotOngoingContributionMode.allCases) { mode in
                        Button { pendingMode = mode } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: mode == .resultsOnly ? "chart.xyaxis.line" : "hand.tap")
                                    .foregroundStyle(EvolvTheme.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mode.title)
                                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(EvolvTheme.text)
                                    Text(mode.detail)
                                        .font(.system(size: 11.5, design: .rounded))
                                        .foregroundStyle(EvolvTheme.textMuted)
                                        .lineSpacing(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(13)
                            .background(RoundedRectangle(cornerRadius: 15).fill(EvolvTheme.surfaceHi))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let message {
                    Text(message)
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
            }
        }
        .alert("Enable future contribution?", isPresented: Binding(
            get: { pendingMode != nil },
            set: { if !$0 { pendingMode = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingMode = nil }
            Button("Enable") {
                guard let mode = pendingMode else { return }
                do {
                    try coordinator.enableOngoingContribution(mode)
                    message = coordinator.lastMessage
                } catch {
                    message = error.localizedDescription
                }
                pendingMode = nil
            }
        } message: {
            Text(pendingMode?.detail ?? "Only future scans are affected.")
        }
        .alert("Turn off future contribution?", isPresented: $confirmDisable) {
            Button("Cancel", role: .cancel) {}
            Button("Turn off", role: .destructive) {
                Task {
                    do {
                        try await coordinator.disableOngoingContribution()
                        message = coordinator.lastMessage
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Pending future-scan uploads will be canceled. Data already shared remains until you delete all shared pilot data or it reaches its retention date.")
        }
    }
}

struct PilotProgressContributionCard: View {
    let scan: Scan
    let analysis: ScanAnalysis

    @State private var coordinator = PilotSubmissionCoordinator.shared
    @State private var scope: PilotShareScope = .resultsOnly
    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var photoApproval = false
    @State private var errorMessage: String?

    private var existing: PilotSubmissionRecord? {
        coordinator.submissions.last {
            $0.localSessionID == scan.id && $0.structuredPayload.contributionType == .progressScan
        }
    }

    private var choices: [PilotPhotoChoice] {
        PilotProgressResultsBuilder.photoChoices(scan: scan)
    }

    private var isEligible: Bool {
        PilotOngoingContributionPolicy.canContribute(
            enrollment: coordinator.enrollment,
            hasCompletedConsistencySubmission: coordinator.hasCompletedConsistencySubmission,
            scan: scan,
            analysis: analysis
        )
    }

    var body: some View {
        if isEligible {
            GlassCard(padding: 18, cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 13) {
                    Label("Optional pilot contribution", systemImage: "lock.shield")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)

                    if let existing, existing.status == .completed {
                        Label(
                            existing.selectedPhotos.isEmpty
                                ? "Results shared · no photos"
                                : "Results and \(existing.selectedPhotos.count) selected photos shared",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                    } else if coordinator.ongoingMode == .resultsOnly {
                        Text("Your separate future-results choice applies to this scan. Only structured analysis is included; no photo bytes or filenames are sent.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                            .lineSpacing(2)
                        submissionStatus(existing)
                        EvolvPrimaryButton(
                            title: coordinator.isWorking ? "Sharing…" : "Share results now",
                            icon: "chart.xyaxis.line",
                            enabled: !coordinator.isWorking
                        ) { submit() }
                    } else {
                        Text("Nothing from this scan is shared until you choose below.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                        Picker("Sharing", selection: $scope) {
                            ForEach(PilotShareScope.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if scope == .resultsAndSelectedPhotos {
                            Text("Select each required-pose photo you approve. Showcase and unselected photos stay on this iPhone.")
                                .font(.system(size: 11.5, design: .rounded))
                                .foregroundStyle(EvolvTheme.textMuted)
                            photoGrid
                            Toggle("I approve uploading only the selected photos", isOn: $photoApproval)
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .tint(EvolvTheme.accent)
                        }
                        submissionStatus(existing)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(EvolvTheme.stalled)
                        }
                        EvolvPrimaryButton(
                            title: coordinator.isWorking ? "Sharing…" : "Share this scan",
                            icon: "lock.shield",
                            enabled: !coordinator.isWorking
                                && (scope == .resultsOnly || (photoApproval && !selectedPhotoIDs.isEmpty))
                        ) { submit() }
                    }
                }
            }
            .onAppear {
                if let existing {
                    scope = existing.consent.shareScope
                    selectedPhotoIDs = Set(existing.selectedPhotos.map(\.captureID))
                    photoApproval = !selectedPhotoIDs.isEmpty
                }
            }
        }
    }

    @ViewBuilder
    private func submissionStatus(_ record: PilotSubmissionRecord?) -> some View {
        if let record, record.status != .completed {
            Label(record.status.title, systemImage: "arrow.clockwise.icloud")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(EvolvTheme.stable)
        }
    }

    private var photoGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(choices) { choice in
                Button { toggle(choice.captureID) } label: {
                    ZStack(alignment: .topTrailing) {
                        photo(for: choice)
                            .aspectRatio(0.72, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        Image(systemName: selectedPhotoIDs.contains(choice.captureID) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedPhotoIDs.contains(choice.captureID) ? EvolvTheme.accent : .white)
                            .shadow(radius: 2)
                            .padding(6)
                        Text(choice.pose.shortLabel)
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func photo(for choice: PilotPhotoChoice) -> some View {
        if let capture = scan.captures.first(where: { $0.id == choice.captureID }),
           let image = PhotoStore.loadImage(named: capture.imageFilename) {
            Image(uiImage: image).resizable()
        } else {
            Rectangle().fill(EvolvTheme.surfaceHi)
                .overlay(Image(systemName: "photo").foregroundStyle(EvolvTheme.textFaint))
        }
    }

    private func toggle(_ id: UUID) {
        if selectedPhotoIDs.contains(id) { selectedPhotoIDs.remove(id) }
        else { selectedPhotoIDs.insert(id) }
        photoApproval = false
    }

    private func submit() {
        Task {
            do {
                _ = try await coordinator.prepareProgressAndSubmit(
                    scan: scan,
                    analysis: analysis,
                    shareScope: coordinator.ongoingMode == .resultsOnly ? .resultsOnly : scope,
                    selectedPhotos: selectedPhotoIDs,
                    photoApprovalConfirmed: photoApproval
                )
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
