import SwiftUI
import UserNotifications

// MARK: - Settings root

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            NavigationStack {
                ZStack {
                    AmbientBackground()
                    ScrollView {
                        VStack(spacing: 14) {
                            SettingsRowLink(
                                icon: "person.crop.circle",
                                title: "Profile",
                                subtitle: profileSubtitle,
                                destination: { ProfileSettingsView() }
                            )
                            SettingsRowLink(
                                icon: "bell",
                                title: "Notifications",
                                subtitle: notificationsSubtitle,
                                destination: { NotificationSettingsView() }
                            )
                            SettingsRowLink(
                                icon: "ruler",
                                title: "Units",
                                subtitle: "\(app.profile.massUnit.label) · \(app.profile.lengthUnit.label)",
                                destination: { UnitsSettingsView() }
                            )
                            SettingsRowLink(
                                icon: "lock.shield",
                                title: "Privacy & Data",
                                subtitle: "Stored locally on this device",
                                destination: { PrivacySettingsView() }
                            )
                            SettingsRowLink(
                                icon: "sparkles",
                                title: "Subscription",
                                subtitle: "Free plan",
                                destination: { SubscriptionSettingsView() }
                            )
            
                            Text("Your data belongs to you.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(EvolvTheme.textFaint)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                                .padding(.bottom, 32)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .scrollIndicators(.hidden)
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .tint(EvolvTheme.accent)
                    }
                }
            }
        }
        .trackView("SettingsView")
    }

    private var profileSubtitle: String {
        app.profile.goal.rawValue
    }

    private var notificationsSubtitle: String {
        guard app.profile.remindersEnabled else { return "Off" }
        let time = String(format: "%d:%02d", displayHour(app.profile.reminderHour), app.profile.reminderMinute)
        let suffix = app.profile.reminderHour >= 12 ? "PM" : "AM"
        let wds = app.profile.effectiveScanWeekdays
        let daysLabel = wds.map { weekdayShort($0) }.joined(separator: "·")
        switch app.profile.cadence {
        case .daily:    return "Daily · \(time) \(suffix)"
        case .weekly:   return "Weekly · \(daysLabel) · \(time) \(suffix)"
        case .biweekly: return "Biweekly · \(daysLabel) · \(time) \(suffix)"
        case .monthly:  return "Monthly · day \(app.profile.scanDayOfMonth) · \(time) \(suffix)"
        }
    }

    private func displayHour(_ h: Int) -> Int {
        let mod = h % 12
        return mod == 0 ? 12 : mod
    }

    private func weekdayShort(_ wd: Int) -> String {
        ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][max(0, min(6, wd - 1))]
    }
}

// MARK: - Settings row

private struct SettingsRowLink<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(EvolvTheme.accent.opacity(0.10))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(EvolvTheme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EvolvTheme.text)
                    Text(subtitle)
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(EvolvTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EvolvTheme.textFaint)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(EvolvTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(EvolvTheme.stroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared settings building blocks

struct SettingsGroup<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(EvolvTheme.textFaint)
                    .padding(.horizontal, 6)
            }
            VStack(spacing: 0) { content }
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(EvolvTheme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(EvolvTheme.stroke, lineWidth: 1)
                        }
                }
            if let footer {
                Text(footer)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(EvolvTheme.textMuted)
                    .lineSpacing(2)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
            }
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().background(EvolvTheme.stroke).padding(.leading, 18)
    }
}

#Preview {
    SettingsView().environment(AppState())
}
