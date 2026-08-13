import SwiftUI

// MARK: - Privacy & Data

struct PrivacySettingsView: View {
    @Environment(AppState.self) private var app

    @State private var confirmDeleteScans = false
    @State private var confirmResetAll = false
    @State private var showManageScans = false
    @State private var showExportSheet = false
    @State private var confirmLocalOnlyStorage = false
    @State private var storagePreferenceError: String? = nil

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 18) {
                    privacyHero

                    SettingsGroup(
                        header: "Cloud insights",
                        footer: "When enabled, Evolv sends an anonymous derived trend summary—not photos, filenames, landmarks, or raw measurements—to its insight service."
                    ) {
                        Toggle(isOn: cloudInsightsBinding) {
                            HStack(spacing: 14) {
                                Image(systemName: "cloud")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(EvolvTheme.text)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cloud-written insights")
                                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(EvolvTheme.text)
                                    Text(app.profile.usesCloudInsights ? "Enabled" : "Off — summaries are generated on device")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(EvolvTheme.textMuted)
                                }
                            }
                        }
                        .tint(EvolvTheme.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }

                    SettingsGroup(
                        header: "Consistency pilot",
                        footer: "Pilot sharing and cloud-written insights are separate choices. Joining one never enables the other."
                    ) {
                        NavigationLink(destination: PilotDataSharingView()) {
                            HStack(spacing: 14) {
                                Image(systemName: "checkmark.shield")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(EvolvTheme.text)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pilot data sharing")
                                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(EvolvTheme.text)
                                    Text(PilotStudyStore.loadEnrollment()?.status == .active ? "Active — review or withdraw" : "Off or not enrolled")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(EvolvTheme.textMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(EvolvTheme.textFaint)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                    }

                    SettingsGroup(
                        header: "Backup & recovery",
                        footer: "Apple backup is allowed by default. Local-only mode excludes Evolv's local scan and analysis files from future Apple device backups and can make scans unrecoverable if this iPhone is lost, replaced, or erased."
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Scans use Evolv's private app storage. Apple may include that app data in an iCloud or computer backup, depending on your settings.")
                                .font(.system(size: 12.5, design: .rounded))
                                .foregroundStyle(EvolvTheme.textMuted)
                                .lineSpacing(3)
                            Toggle(isOn: localOnlyStorageBinding) {
                                HStack(spacing: 12) {
                                    Image(systemName: app.profile.usesLocalOnlyStorage ? "iphone.and.arrow.forward" : "externaldrive.badge.icloud")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(EvolvTheme.text)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Keep Evolv data off Apple backups")
                                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                            .foregroundStyle(EvolvTheme.text)
                                        Text(app.profile.usesLocalOnlyStorage ? "Local-only mode" : "Apple backup allowed")
                                            .font(.system(size: 11.5, design: .rounded))
                                            .foregroundStyle(EvolvTheme.textMuted)
                                    }
                                }
                            }
                            .tint(EvolvTheme.accent)
                            Link(destination: URL(string: "https://support.apple.com/108922")!) {
                                HStack {
                                    Text("How to manage Apple backups")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(EvolvTheme.accent)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }

                    SettingsGroup(header: "Manage") {
                        actionRow(
                            icon: "rectangle.stack",
                            title: "Manage stored scans",
                            subtitle: "\(app.scans.count) scan\(app.scans.count == 1 ? "" : "s") on this device",
                            tint: EvolvTheme.text
                        ) {
                            showManageScans = true
                        }
                        SettingsDivider()
                        actionRow(
                            icon: "square.and.arrow.up",
                            title: "Export your data",
                            subtitle: "Save a copy you can keep",
                            tint: EvolvTheme.text
                        ) {
                            showExportSheet = true
                        }
                    }

                    SettingsGroup(
                        header: "Delete",
                        footer: "Deletions are permanent inside Evolv. Apple device backups may retain an earlier app-data snapshot until those backups are updated or removed."
                    ) {
                        actionRow(
                            icon: "trash",
                            title: "Delete all scan data",
                            subtitle: "Removes scans and measurements",
                            tint: EvolvTheme.stalled
                        ) {
                            confirmDeleteScans = true
                        }
                        SettingsDivider()
                        actionRow(
                            icon: "exclamationmark.triangle",
                            title: "Reset Evolv",
                            subtitle: "Erase profile, scans, and onboarding",
                            tint: EvolvTheme.stalled
                        ) {
                            confirmResetAll = true
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete all scan data?", isPresented: $confirmDeleteScans) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                app.deleteAllScanData()
            }
        } message: {
            Text("This removes every scan, photo, and measurement from this device. Profile and preferences are kept.")
        }
        .alert("Reset Evolv?", isPresented: $confirmResetAll) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                app.resetAll()
            }
        } message: {
            Text("This erases the local profile, scans, measurements, and onboarding. It does not delete pilot data already shared with Evolv; use Pilot data sharing first if you want that deleted too.")
        }
        .alert("Keep scans only on this iPhone?", isPresented: $confirmLocalOnlyStorage) {
            Button("Cancel", role: .cancel) {}
            Button("Use Local-Only Mode", role: .destructive) {
                updateLocalOnlyStorage(true)
            }
        } message: {
            Text("Evolv will exclude its local scan and analysis files from future Apple device backups. If you delete Evolv or lose this iPhone, these scans may not be recoverable.")
        }
        .alert(
            "Couldn't update storage preference",
            isPresented: Binding(
                get: { storagePreferenceError != nil },
                set: { if !$0 { storagePreferenceError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { storagePreferenceError = nil }
        } message: {
            Text(storagePreferenceError ?? "Your previous setting is unchanged.")
        }
        .sheet(isPresented: $showManageScans) {
            ManageScansSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportDataSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var privacyHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(EvolvTheme.accent.opacity(0.14)).frame(width: 44, height: 44)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(EvolvTheme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your data belongs to you.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text("Your photos stay private unless you explicitly select pilot photos to share.")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                privacyBullet("camera", "Your photos stay on this iPhone unless you explicitly choose specific photos to share with Evolv.")
                privacyBullet("lock", "Scan files use complete protection while your iPhone is locked.")
                privacyBullet("wifi.slash", "Evolv works offline. Cloud-written wording is optional.")
                privacyBullet("icloud", app.profile.usesLocalOnlyStorage
                              ? "Local-only mode excludes Evolv data from future Apple device backups."
                              : "Apple may include app data in device backups. You can opt into local-only mode below.")
                privacyBullet("hand.raised", "Delete anything, anytime, with one tap.")
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(EvolvTheme.stroke, lineWidth: 1)
                }
        }
    }

    private var cloudInsightsBinding: Binding<Bool> {
        Binding(
            get: { app.profile.usesCloudInsights },
            set: { enabled in
                app.profile.cloudInsightsEnabled = enabled
                app.save()
            }
        )
    }

    private var localOnlyStorageBinding: Binding<Bool> {
        Binding(
            get: { app.profile.usesLocalOnlyStorage },
            set: { enabled in
                if enabled {
                    confirmLocalOnlyStorage = true
                } else {
                    updateLocalOnlyStorage(false)
                }
            }
        )
    }

    private func updateLocalOnlyStorage(_ enabled: Bool) {
        do {
            try app.setLocalOnlyStorage(enabled)
        } catch {
            storagePreferenceError = error.localizedDescription
        }
    }

    private func privacyBullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EvolvTheme.accent)
                .frame(width: 16, height: 16)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .lineSpacing(2)
        }
    }

    private func actionRow(icon: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EvolvTheme.textFaint)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Manage scans sheet

private struct ManageScansSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete: Scan? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                if app.scans.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(EvolvTheme.textFaint)
                        Text("No scans stored")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(app.scans.sorted(by: { $0.date > $1.date })) { scan in
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(scan.date, format: .dateTime.day().month(.wide).year())
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(EvolvTheme.text)
                                        Text("\(scan.captures.count) photo\(scan.captures.count == 1 ? "" : "s") · \(scan.analysisAvailability?.label ?? "legacy evidence")")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundStyle(EvolvTheme.textMuted)
                                    }
                                    Spacer()
                                    Button {
                                        confirmDelete = scan
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(EvolvTheme.stalled)
                                            .frame(width: 34, height: 34)
                                            .background(Circle().fill(EvolvTheme.stalled.opacity(0.12)))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(16)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(EvolvTheme.surface)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(EvolvTheme.stroke, lineWidth: 1)
                                        }
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Manage scans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.tint(EvolvTheme.accent)
                }
            }
            .alert(item: $confirmDelete) { scan in
                Alert(
                    title: Text("Delete this scan?"),
                    message: Text("This removes the scan and its photos permanently."),
                    primaryButton: .destructive(Text("Delete")) {
                        app.deleteScan(scan)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}

// MARK: - Export sheet (placeholder)

private struct ExportDataSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            EvolvTheme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Capsule().fill(EvolvTheme.stroke).frame(width: 36, height: 4).padding(.top, 12)
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(EvolvTheme.accent)
                    .padding(.top, 8)
                Text("Export coming soon")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(EvolvTheme.text)
                Text("We're preparing a clean, portable bundle of your scans, measurements, timeline notes, and pilot-sharing receipts. A future export will distinguish local scan data from anything you explicitly shared with the pilot.")
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 28)
                Spacer()
                EvolvPrimaryButton(title: "Close") { dismiss() }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Subscription

struct SubscriptionSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var showPaywall = false
    @State private var restoreMessage: String? = nil
    @State private var isRestoring = false

    private var isPremium: Bool { app.isPremium }
    private var planLabel: String {
        guard let raw = app.profile.subscriptionPlan,
              let plan = PurchaseService.Plan(rawValue: raw) else { return "Free" }
        return "Evolv Premium · \(plan.title)"
    }
    private var trialFootnote: String? {
        guard let end = app.profile.trialEndsAt, end > Date() else { return nil }
        let days = max(1, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
        return "Trial ends in \(days) day\(days == 1 ? "" : "s")."
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 18) {
                    planCard

                    if !isPremium {
                        Button { showPaywall = true } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Upgrade to Evolv Premium")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(EvolvTheme.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(EvolvTheme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        Task { await beginRestore() }
                    } label: {
                        HStack(spacing: 8) {
                            if isRestoring { ProgressView().tint(EvolvTheme.textMuted) }
                            Text(isRestoring ? "Restoring…" : "Restore purchases")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(EvolvTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(EvolvTheme.stroke, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRestoring)

                    if let msg = restoreMessage {
                        Text(msg)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(EvolvTheme.textMuted)
                            .transition(.opacity)
                    }

                    Text(footerCopy)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(EvolvTheme.textFaint)
                        .lineSpacing(2)
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .animation(.easeInOut(duration: 0.25), value: restoreMessage)
    }

    private var footerCopy: String {
        if isPremium {
            return "Manage or cancel your subscription anytime from the App Store. Scan photos stay local unless you explicitly select specific photos for the invited consistency pilot."
        }
        return "Premium unlocks unlimited scans, full AI analysis, and long-term comparisons. Billing is currently in test mode — purchases on this device do not bill a real card."
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Group {
                    if isPremium {
                        HStack(spacing: 6) {
                            Image("evolv-logo")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 12)
                            Text("PREMIUM")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .tracking(1.5)
                                .foregroundStyle(EvolvTheme.textFaint)
                        }
                    } else {
                        Text("CURRENT PLAN")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(EvolvTheme.textFaint)
                    }
                }
                Spacer()
                Text(isPremium ? "Active" : "Free")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isPremium ? EvolvTheme.accent : EvolvTheme.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill((isPremium ? EvolvTheme.accent : EvolvTheme.textMuted).opacity(0.14)))
            }
            Text(isPremium ? planLabel : "Free")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(EvolvTheme.text)
            Text(isPremium
                 ? "Unlimited scans, full AI analysis, advanced comparisons."
                 : "Limited scans, basic timeline, no advanced comparisons.")
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(EvolvTheme.textMuted)
                .lineSpacing(2)
            if let trial = trialFootnote {
                Text(trial)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(EvolvTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(EvolvTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(EvolvTheme.stroke, lineWidth: 1)
                }
        }
    }

    @MainActor
    private func beginRestore() async {
        isRestoring = true
        let success = await PurchaseService.shared.restore()
        if success {
            app.syncSubscriptionFromPurchaseService()
            restoreMessage = "Purchases restored."
        } else {
            restoreMessage = "No purchases to restore on this device."
        }
        isRestoring = false
        try? await Task.sleep(nanoseconds: 2_400_000_000)
        restoreMessage = nil
    }
}
