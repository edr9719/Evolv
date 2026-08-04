import SwiftUI
import UserNotifications

// MARK: - Notifications

struct NotificationSettingsView: View {
    @Environment(AppState.self) private var app

    @State private var enabled: Bool = false
    @State private var cadence: Cadence = .weekly
    @State private var weekdays: [Int] = [2]   // ordered selection (newest pushed in)
    @State private var dayOfMonth: Int = 1
    @State private var reminderDate: Date = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()

    @State private var permission: UNAuthorizationStatus = .notDetermined
    @State private var showPermissionPrompt = false
    @State private var testSentToast: Bool = false

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 18) {
                    SettingsGroup(footer: permissionFooter) {
                        HStack {
                            Image(systemName: "bell")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(EvolvTheme.accent)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan reminders")
                                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(EvolvTheme.text)
                                Text("A gentle nudge on your scan day.")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(EvolvTheme.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $enabled)
                                .labelsHidden()
                                .tint(EvolvTheme.accent)
                                .onChange(of: enabled) { _, newValue in
                                    handleToggle(newValue)
                                }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }

                    SettingsGroup(header: "Frequency") {
                        ForEach(Cadence.allCases) { c in
                            CadenceSelectionRow(cadence: c, isSelected: cadence == c) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    cadence = c
                                    normalizeWeekdaysForCadence()
                                }
                                persist()
                            }
                            if c != Cadence.allCases.last {
                                SettingsDivider()
                            }
                        }
                    }

                    if cadence != .monthly {
                        SettingsGroup(header: scheduleHeader, footer: scheduleFooter) {
                            WeekdayPickerRow(
                                weekdays: $weekdays,
                                mode: pickerMode,
                                onChange: persist
                            )
                        }
                    }

                    if cadence == .monthly {
                        SettingsGroup(header: "Scan day") {
                            DayOfMonthPickerRow(day: $dayOfMonth, onChange: persist)
                        }
                    }

                    if enabled {
                        SettingsGroup(header: "Reminder time") {
                            HStack {
                                Text("Time")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(EvolvTheme.text)
                                Spacer()
                                DatePicker("", selection: $reminderDate, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .tint(EvolvTheme.accent)
                                    .onChange(of: reminderDate) { _, _ in persist() }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                        }

                        SettingsGroup(footer: "Sends a sample reminder in 5 seconds so you can confirm notifications are working.") {
                            Button {
                                NotificationManager.sendTestNotification()
                                withAnimation { testSentToast = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                                    withAnimation { testSentToast = false }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "paperplane")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(EvolvTheme.accent)
                                        .frame(width: 26)
                                    Text(testSentToast ? "Test scheduled — check in 5 seconds" : "Send a test notification")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(EvolvTheme.text)
                                    Spacer()
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .disabled(permission != .authorized && permission != .provisional)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            load()
            Task { permission = await NotificationManager.authorizationStatus() }
        }
        .alert("Notifications are off", isPresented: $showPermissionPrompt) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {
                enabled = false
                persist()
            }
        } message: {
            Text("Enable notifications for Evolv in iOS Settings to receive scan reminders.")
        }
    }

    // MARK: - Logic

    private var pickerMode: WeekdayPickerRow.Mode {
        switch cadence {
        case .daily: return .lockedAll
        case .weekly: return .single
        case .biweekly: return .multi(max: 2)
        case .monthly: return .single
        }
    }

    private var scheduleHeader: String {
        switch cadence {
        case .daily: return "Scan days"
        case .weekly: return "Scan day"
        case .biweekly: return "Scan days"
        case .monthly: return "Preferred weekday"
        }
    }

    private var scheduleFooter: String {
        switch cadence {
        case .daily: return "Daily cadence reminds you every day at the chosen time."
        case .weekly: return "Pick one day each week to keep conditions consistent."
        case .biweekly: return "Pick up to two days — Evolv schedules them every other week."
        case .monthly: return ""
        }
    }

    private var permissionFooter: String {
        if !enabled { return "Optional. Helps you stay consistent without feeling pressured." }
        switch permission {
        case .denied: return "Notifications are disabled in iOS Settings. Open Settings to allow them."
        case .notDetermined: return "We'll ask for permission when you turn this on."
        default: return "Reminders are scheduled locally on this device only."
        }
    }

    private func normalizeWeekdaysForCadence() {
        switch cadence {
        case .daily:
            weekdays = [1,2,3,4,5,6,7]
        case .weekly, .monthly:
            if let first = weekdays.first {
                weekdays = [first]
            } else {
                weekdays = [2]
            }
        case .biweekly:
            // Keep up to 2 days; if empty, seed with Monday.
            if weekdays.isEmpty { weekdays = [2] }
            weekdays = Array(weekdays.prefix(2))
        }
    }

    private func handleToggle(_ on: Bool) {
        if on {
            Task {
                let status = await NotificationManager.authorizationStatus()
                if status == .notDetermined {
                    let granted = await NotificationManager.requestPermission()
                    let current = await NotificationManager.authorizationStatus()
                    await MainActor.run {
                        permission = current
                        if !granted {
                            enabled = false
                        }
                        persist()
                    }
                } else if status == .denied {
                    await MainActor.run {
                        permission = status
                        showPermissionPrompt = true
                    }
                } else {
                    await MainActor.run {
                        permission = status
                        persist()
                    }
                }
            }
        } else {
            persist()
        }
    }

    private func load() {
        enabled = app.profile.remindersEnabled
        cadence = app.profile.cadence
        weekdays = app.profile.scanWeekdays.isEmpty ? [app.profile.scanWeekday] : app.profile.scanWeekdays
        dayOfMonth = app.profile.scanDayOfMonth
        var comps = DateComponents()
        comps.hour = app.profile.reminderHour
        comps.minute = app.profile.reminderMinute
        if let d = Calendar.current.date(from: comps) { reminderDate = d }
        normalizeWeekdaysForCadence()
    }

    private func persist() {
        normalizeWeekdaysForCadence()
        app.profile.remindersEnabled = enabled
        app.profile.cadence = cadence
        app.profile.scanWeekdays = weekdays
        app.profile.scanWeekday = weekdays.first ?? 2  // legacy compat
        app.profile.scanDayOfMonth = dayOfMonth
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
        app.profile.reminderHour = comps.hour ?? 20
        app.profile.reminderMinute = comps.minute ?? 0
        app.save()
    }
}

// MARK: - Cadence selection row

private struct CadenceSelectionRow: View {
    let cadence: Cadence
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cadence.rawValue)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text(cadence.description)
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(isSelected ? EvolvTheme.accent : EvolvTheme.stroke, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle().fill(EvolvTheme.accent).frame(width: 10, height: 10)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Weekday picker (single / multi / locked-all)

struct WeekdayPickerRow: View {
    enum Mode: Equatable {
        case single
        case multi(max: Int)
        case lockedAll
    }

    @Binding var weekdays: [Int]
    let mode: Mode
    let onChange: () -> Void

    private let symbols: [(Int, String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(symbols, id: \.0) { entry in
                let wd = entry.0
                let isOn = weekdays.contains(wd)
                Button {
                    handleTap(wd)
                } label: {
                    Text(entry.1)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(foreground(isOn: isOn))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(background(isOn: isOn))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(strokeColor(isOn: isOn), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(mode == .lockedAll)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private func handleTap(_ wd: Int) {
        switch mode {
        case .lockedAll:
            return
        case .single:
            if weekdays.first != wd {
                withAnimation(.easeInOut(duration: 0.18)) { weekdays = [wd] }
                onChange()
            }
        case .multi(let max):
            withAnimation(.easeInOut(duration: 0.18)) {
                if let idx = weekdays.firstIndex(of: wd) {
                    // Allow removal only if more than one selected remains.
                    if weekdays.count > 1 {
                        weekdays.remove(at: idx)
                    }
                } else {
                    weekdays.append(wd)
                    if weekdays.count > max {
                        weekdays.removeFirst()
                    }
                }
            }
            onChange()
        }
    }

    private func foreground(isOn: Bool) -> Color {
        if mode == .lockedAll { return EvolvTheme.background }
        return isOn ? EvolvTheme.background : EvolvTheme.textMuted
    }

    private func background(isOn: Bool) -> Color {
        if mode == .lockedAll { return EvolvTheme.accent.opacity(0.85) }
        return isOn ? EvolvTheme.accent : EvolvTheme.surfaceHi.opacity(0.6)
    }

    private func strokeColor(isOn: Bool) -> Color {
        if mode == .lockedAll { return .clear }
        return isOn ? .clear : EvolvTheme.stroke
    }
}

// MARK: - Day of month picker

private struct DayOfMonthPickerRow: View {
    @Binding var day: Int
    let onChange: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(1...28, id: \.self) { d in
                let selected = day == d
                Button {
                    day = d
                    onChange()
                } label: {
                    Text("\(d)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? EvolvTheme.background : EvolvTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? EvolvTheme.accent : EvolvTheme.surfaceHi.opacity(0.6))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}
