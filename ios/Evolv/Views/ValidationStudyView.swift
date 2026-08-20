import SwiftUI

struct ValidationStudyView: View {
    @Environment(AppState.self) private var app

    @State private var selectedCamera = CameraPreferenceStore.load()
    @State private var useEligibleScan = false
    @State private var showNewSessionSetup = false
    @State private var captureContext: ValidationCaptureContext?
    @State private var reportingChange = false
    @State private var selectedDeviations: Set<ValidationDeviationReason> = []
    @State private var evaluatingSessionID: UUID?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var pilot = PilotSubmissionCoordinator.shared
    @State private var showPilotEnrollment = false

    private var latestSession: ValidationStudySession? { app.latestValidationSession }
    private var eligibleAnchor: Scan? { app.eligibleValidationAnchor() }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Help test Evolv")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            app.refreshValidationSessionEligibility()
        }
        .fullScreenCover(item: $captureContext) { context in
            CaptureFlowView(
                validationContext: context,
                onValidationSetSaved: { _ in
                    captureContext = nil
                }
            )
        }
        .sheet(isPresented: $showPilotEnrollment) {
            PilotEnrollmentSheet()
        }
        .task {
            await pilot.retryPending()
        }
        .alert("Couldn't save the consistency test", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .trackView("ValidationStudyView")
    }

    @ViewBuilder
    private var content: some View {
        if let session = latestSession,
           session.status == .completed,
           !hasActivePilot,
           !showNewSessionSetup {
            completedView(session)
        } else if !hasActivePilot {
            pilotEnrollmentRequiredView
        } else if showNewSessionSetup || latestSession == nil {
            setupView
        } else if let session = latestSession {
            switch session.status {
            case .active:
                activeSessionView(session)
            case .evaluating:
                evaluatingView(session)
            case .completed:
                completedView(session)
            case .protocolIneligible, .abandoned:
                ineligibleView(session)
            }
        }
    }

    private var hasActivePilot: Bool {
        pilot.enrollment?.status == .active
    }

    private var pilotEnrollmentRequiredView: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("INVITED PILOT")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(EvolvTheme.accent)
                Text("Join before starting the official test")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .accessibilityIdentifier("validation.pilot.enrollment-required")
                Text("The five-set protocol takes about 20–30 minutes. First review what the pilot checks, give consent, enter your invitation code, and choose what you may want to share.")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(3)
            }

            GlassCard(padding: 18, cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 11) {
                    instruction("Nothing uploads automatically.")
                    instruction("After Set 5, you review results and approve any photos one by one.")
                    instruction("Your normal timeline remains stored on this iPhone.")
                }
            }

            EvolvPrimaryButton(title: "Review pilot & join", icon: "checkmark.shield") {
                showPilotEnrollment = true
            }
            .accessibilityIdentifier("validation.pilot.join-required")

            Text("This screen is the invited pilot. It is not a local-only diagnostic test.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(EvolvTheme.textFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CONSISTENCY TEST")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(EvolvTheme.accent)
                Text("Complete five short sets in the same conditions so we can check whether Evolv gives consistent results.")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .lineSpacing(3)
                Text("Allow about 20–30 minutes. This tests same-session consistency—not fitness progress or measurement accuracy.")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(3)
            }

            instructionCard

            SettingsGroup(
                header: "Camera",
                footer: "The selected camera is locked for all five sets because front and rear lenses can produce different geometry."
            ) {
                cameraPicker
                    .padding(14)
            }

            freshSetOneCard

            VStack(spacing: 10) {
                EvolvPrimaryButton(title: "Start invited consistency test", icon: "camera.fill") {
                    startSession()
                }
                .accessibilityIdentifier("validation.official.start")
                Label(
                    "Nothing is shared until you review the completed test.",
                    systemImage: "lock.shield"
                )
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var freshSetOneCard: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "viewfinder.circle")
                .foregroundStyle(EvolvTheme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text("A fresh Set 1 is required")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Text("Before Set 2, Evolv will run its full on-device comparison-evidence check. If one pose is unusable, you retake only that pose.")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(EvolvTheme.stroke, lineWidth: 1))
        }
    }

    private var pilotEnrollmentCard: some View {
        GlassCard(padding: 18, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                if let enrollment = pilot.enrollment, enrollment.status == .active {
                    Label("Invited pilot active", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                    Text("Current choice: \(enrollment.consent.shareScope.title). After Set 5, you will review the package and can switch to results only or select individual photos.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(2)
                } else {
                    Text("Have a pilot invite?")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text("Join before starting if you may want to share this five-set test. Joining never uploads existing scans.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                    Button("Review sharing choices") { showPilotEnrollment = true }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.accent)
                }
            }
        }
    }

    private var instructionCard: some View {
        GlassCard(padding: 18, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 13) {
                Text("BEFORE YOU START")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(EvolvTheme.accent)
                instruction("Complete all five sets in one session.")
                instruction("Wear the same fitted or minimal clothing throughout.")
                instruction("Keep the same room and lighting.")
                instruction("Keep the iPhone upright at about waist height.")
                instruction("Mark the phone and foot positions if possible.")
                instruction("Do not eat, drink, exercise, or change clothing during the test.")
                instruction("Fully step away and reposition both yourself and the phone between sets.")
            }
        }
    }

    private func instruction(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EvolvTheme.accent)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .lineSpacing(2)
        }
    }

    private var cameraPicker: some View {
        HStack(spacing: 10) {
            cameraChoice(.front, icon: "person.crop.rectangle")
            cameraChoice(.rear, icon: "camera")
        }
    }

    private func cameraChoice(_ position: CaptureCameraPosition, icon: String) -> some View {
        let lockedByAnchor = useEligibleScan && eligibleAnchor != nil
        return Button {
            guard !lockedByAnchor else { return }
            selectedCamera = position
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(position.label)
                if selectedCamera == position { Image(systemName: "checkmark") }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(selectedCamera == position ? EvolvTheme.background : EvolvTheme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selectedCamera == position ? EvolvTheme.accent : EvolvTheme.surfaceHi)
            }
        }
        .buttonStyle(.plain)
        .disabled(lockedByAnchor)
        .accessibilityLabel("Use \(position.label.lowercased()) camera for all five sets")
    }

    private func eligibleAnchorCard(_ scan: Scan) -> some View {
        GlassCard(padding: 18, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $useEligibleScan) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Use today's recent scan as Set 1")
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                        Text("Captured at \(scan.date.formatted(date: .omitted, time: .shortened)) with the \(selectedCamera.label) camera")
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                    }
                }
                .tint(EvolvTheme.accent)
                Text(useEligibleScan
                     ? "You will capture Sets 2–5. Finish within 60 minutes of that scan, and confirm that clothing, room, lighting, phone height, and your pre-scan routine still match."
                     : "You will capture a new Set 1. Because today's progress scan already exists, the new five sets will stay outside progress analysis.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(EvolvTheme.textFaint)
                    .lineSpacing(2)
            }
        }
        .onChange(of: useEligibleScan) { _, enabled in
            guard enabled,
                  let metadata = ValidationStudyPolicy.cameraConfiguration(for: scan.captures) else { return }
            selectedCamera = metadata.position
        }
    }

    private var timelineRuleCard: some View {
        let hasCanonicalToday = app.todayCanonicalScan != nil
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .foregroundStyle(EvolvTheme.accent)
            Text(hasCanonicalToday
                 ? "Today's progress scan cannot be used for this protocol. A new Set 1 will be saved as a consistency anchor and will not affect progress."
                 : "Set 1 will also become today's progress scan. Sets 2–5 remain consistency repeats and cannot affect progress.")
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .lineSpacing(2)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(EvolvTheme.stroke, lineWidth: 1))
        }
    }

    private func activeSessionView(_ session: ValidationStudySession) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            sessionHeader(session)
            setProgress(session)

            if let setNumber = session.awaitingConditionsSetNumber {
                conditionsView(session: session, setNumber: setNumber)
            } else {
                GlassCard(padding: 20, cornerRadius: 24) {
                    VStack(spacing: 14) {
                        Image(systemName: "figure.stand.line.dotted.figure.stand")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(EvolvTheme.accent)
                        Text(session.draftCaptures.isEmpty
                             ? "Step away and reposition before Set \(session.nextSetNumber)."
                             : "Set \(session.nextSetNumber) is saved partway through.")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.text)
                            .multilineTextAlignment(.center)
                        Text("Keep clothing, lighting, phone height, and marked positions unchanged. Use the \(session.lockedCameraPosition.label) camera.")
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                        EvolvPrimaryButton(
                            title: session.draftCaptures.isEmpty
                                ? "Capture Set \(session.nextSetNumber)"
                                : "Resume Set \(session.nextSetNumber)",
                            icon: "camera.fill"
                        ) {
                            captureContext = app.validationCaptureContext(sessionID: session.id)
                        }
                    }
                }
            }

            Text("You can leave this screen and return within 60 minutes. Completed sets and partial photos are checkpointed locally.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(EvolvTheme.textFaint)
                .lineSpacing(2)
        }
    }

    private func sessionHeader(_ session: ValidationStudySession) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("CONSISTENCY TEST")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(EvolvTheme.accent)
            Text("\(session.completedSetCount) of 5 sets complete")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
            Label("Using \(session.lockedCameraPosition.label) camera for all five sets", systemImage: "lock.fill")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
            Label(
                "Finish by \(session.expiresAt.formatted(date: .omitted, time: .shortened))",
                systemImage: "clock"
            )
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(EvolvTheme.textMuted)
        }
    }

    private func setProgress(_ session: ValidationStudySession) -> some View {
        HStack(spacing: 8) {
            ForEach(1...ValidationStudySession.requiredSetCount, id: \.self) { number in
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(number <= session.completedSetCount ? EvolvTheme.accent : EvolvTheme.surfaceHi)
                            .frame(width: 38, height: 38)
                        if number <= session.completedSetCount {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(EvolvTheme.background)
                        } else {
                            Text("\(number)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(EvolvTheme.textMuted)
                        }
                    }
                    Text("SET")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(EvolvTheme.textFaint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(EvolvTheme.stroke, lineWidth: 1))
        }
    }

    private func conditionsView(session: ValidationStudySession, setNumber: Int) -> some View {
        GlassCard(padding: 20, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SET \(setNumber) SAVED")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(EvolvTheme.accent)
                    Text("Did the test conditions stay the same?")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text("Choose honestly. A change does not erase the photos; it tells Evolv not to treat this as a clean repeat.")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineSpacing(2)
                }

                if !reportingChange {
                    EvolvPrimaryButton(title: "Conditions stayed the same", icon: "checkmark") {
                        saveConditions(sessionID: session.id, setNumber: setNumber, stayedSame: true)
                    }
                    Button {
                        reportingChange = true
                    } label: {
                        Text("Something changed")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 8) {
                        ForEach(ValidationDeviationReason.allCases.filter(\.isUserSelectable)) { reason in
                            Button {
                                if selectedDeviations.contains(reason) { selectedDeviations.remove(reason) }
                                else { selectedDeviations.insert(reason) }
                            } label: {
                                HStack {
                                    Image(systemName: selectedDeviations.contains(reason) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedDeviations.contains(reason) ? EvolvTheme.accent : EvolvTheme.textFaint)
                                    Text(reason.label)
                                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(EvolvTheme.text)
                                    Spacer()
                                }
                                .padding(13)
                                .background(RoundedRectangle(cornerRadius: 14).fill(EvolvTheme.surfaceHi))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    EvolvPrimaryButton(
                        title: selectedDeviations.isEmpty ? "Select what changed" : "Save and continue",
                        icon: "arrow.right",
                        enabled: !selectedDeviations.isEmpty
                    ) {
                        saveConditions(sessionID: session.id, setNumber: setNumber, stayedSame: false)
                    }
                }
            }
        }
    }

    private func evaluatingView(_ session: ValidationStudySession) -> some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)
            ProgressView().tint(EvolvTheme.accent).scaleEffect(1.4)
            Text("Comparing Sets 2–5 with Set 1…")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
                .multilineTextAlignment(.center)
            Text("This runs entirely on this iPhone. Evolv will show unavailable evidence instead of guessing.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .task(id: session.id) {
            guard evaluatingSessionID != session.id else { return }
            evaluatingSessionID = session.id
            do {
                try await app.evaluateValidationSession(sessionID: session.id)
            } catch {
                present(error)
            }
            evaluatingSessionID = nil
        }
    }

    private func completedView(_ session: ValidationStudySession) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 12) {
                Image(systemName: resultIcon(session.result))
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(EvolvTheme.accent)
                Text(session.result?.title ?? "Test complete")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                    .multilineTextAlignment(.center)
                Text(session.result?.detail ?? "The five sets are saved locally.")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity)

            setProgress(session)
            resultSummary(session)

            PilotSubmissionCard(
                session: session,
                scans: app.validationScans(sessionID: session.id)
            )

            PilotOngoingContributionCard()

            GlassCard(padding: 18, cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Local test copy", systemImage: "iphone")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text("\(session.packagePreview.photoCount) photos · \(session.packagePreview.comparisonCount) comparisons · timeline photos remain on this iPhone even if shared pilot data is deleted")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
            }

            Text("Consistency does not prove measurement accuracy or long-term progress detection.")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            EvolvPrimaryButton(title: "Run another test", icon: "arrow.clockwise") {
                showNewSessionSetup = true
                selectedCamera = CameraPreferenceStore.load()
            }
        }
    }

    private func resultSummary(_ session: ValidationStudySession) -> some View {
        let comparisons = session.sets.compactMap(\.comparison)
        let stable = comparisons.flatMap(\.regionalComparisons).filter { $0.status == .stable }.count
        let unavailable = comparisons.flatMap(\.regionalComparisons).filter { $0.status == .unavailable }.count
        let changed = comparisons.flatMap(\.regionalComparisons).filter { $0.status == .increase || $0.status == .decrease }.count
        let diagnostics = actionableDiagnostics(from: comparisons)
        return VStack(spacing: 12) {
            GlassCard(padding: 18, cornerRadius: 20) {
                HStack {
                    resultMetric("\(stable)", label: "STABLE")
                    Divider().overlay(EvolvTheme.stroke)
                    resultMetric("\(unavailable)", label: "UNAVAILABLE")
                    Divider().overlay(EvolvTheme.stroke)
                    resultMetric("\(changed)", label: "CHANGED")
                }
                .frame(height: 54)
            }

            if !diagnostics.isEmpty {
                GlassCard(padding: 18, cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("WHAT NEEDS ATTENTION")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .tracking(1.3)
                            .foregroundStyle(EvolvTheme.textFaint)
                        ForEach(diagnostics) { diagnostic in
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: diagnostic.kind == .systemError ? "exclamationmark.triangle" : "viewfinder.circle")
                                    .foregroundStyle(diagnostic.kind == .systemError ? EvolvTheme.stable : EvolvTheme.accent)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(diagnostic.userTitle)
                                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(EvolvTheme.text)
                                    Text(diagnostic.userGuidance)
                                        .font(.system(size: 11.5, design: .rounded))
                                        .foregroundStyle(EvolvTheme.textMuted)
                                        .lineSpacing(2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func actionableDiagnostics(
        from comparisons: [ValidationSetComparison]
    ) -> [ValidationPoseDiagnostic] {
        var seen: Set<String> = []
        return comparisons
            .flatMap { $0.diagnostics ?? [] }
            .filter { diagnostic in
                let key = "\(diagnostic.pose.rawValue).\(diagnostic.code).\(diagnostic.affectedRegions.map(\.rawValue).joined(separator: "-"))"
                return seen.insert(key).inserted
            }
    }

    private func resultMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
            Text(label)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(EvolvTheme.textFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private func ineligibleView(_ session: ValidationStudySession) -> some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 36)
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 50, weight: .light))
                .foregroundStyle(EvolvTheme.stable)
            Text("This session can no longer be treated as one controlled test.")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
                .multilineTextAlignment(.center)
            Text("A date change, more than 60 minutes, or an edited set makes the protocol ineligible. Evolv kept \(session.completedSetCount) completed set\(session.completedSetCount == 1 ? "" : "s") and \(session.draftCaptures.count) draft photo\(session.draftCaptures.count == 1 ? "" : "s") on this iPhone.")
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Text("Starting again does not silently delete the earlier session.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(EvolvTheme.textFaint)
            EvolvPrimaryButton(title: "Start a new test", icon: "arrow.clockwise") {
                showNewSessionSetup = true
            }
        }
    }

    private func resultIcon(_ result: ValidationConsistencyStatus?) -> String {
        switch result {
        case .consistent: return "checkmark.seal.fill"
        case .limitedEvidence: return "viewfinder.circle"
        case .needsReview: return "exclamationmark.magnifyingglass"
        case .none: return "checkmark.circle"
        }
    }

    private func startSession() {
        do {
            let id = try app.startOfficialValidationSession(
                cameraPosition: selectedCamera
            )
            showNewSessionSetup = false
            reportingChange = false
            selectedDeviations = []
            captureContext = app.validationCaptureContext(sessionID: id)
        } catch {
            present(error)
        }
    }

    private func saveConditions(sessionID: UUID, setNumber: Int, stayedSame: Bool) {
        do {
            try app.recordValidationConditions(
                sessionID: sessionID,
                setNumber: setNumber,
                stayedTheSame: stayedSame,
                deviations: Array(selectedDeviations)
            )
            reportingChange = false
            selectedDeviations = []
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

#Preview {
    NavigationStack { ValidationStudyView() }
        .environment(AppState())
}
