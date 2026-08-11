import Foundation
import UserNotifications

/// Lightweight wrapper around UNUserNotificationCenter for Evolv's scan reminders.
/// All scheduling is local — no remote, no payloads, no tracking.
enum NotificationManager {

    static let reminderIdentifierPrefix = "evolv.scan.reminder"

    // MARK: - Permission

    /// Returns the current authorization status.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { cont in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                cont.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// Requests permission. Returns whether the user granted it.
    @discardableResult
    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Scheduling

    /// Cancel all Evolv scan reminders.
    static func cancelAllReminders() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(reminderIdentifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Re-syncs scheduled reminders from the user's profile.
    /// Safe to call repeatedly. If reminders are disabled, all are cancelled.
    static func sync(with profile: UserProfile) {
        let center = UNUserNotificationCenter.current()
        // Always clear first to avoid duplicate stale schedules.
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(reminderIdentifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            guard profile.remindersEnabled else { return }

            Task {
                let status = await authorizationStatus()
                guard status == .authorized || status == .provisional else { return }
                await MainActor.run { schedule(for: profile) }
            }
        }
    }

    private static func schedule(for profile: UserProfile) {
        let center = UNUserNotificationCenter.current()
        let content = makeContent()

        for request in buildRequests(for: profile, content: content) {
            center.add(request, withCompletionHandler: nil)
        }
    }

    private static func makeContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Time for your scan"
        content.body  = "A consistent capture today keeps your trend honest."
        content.sound = .default
        return content
    }

    private static func buildRequests(
        for profile: UserProfile,
        content: UNMutableNotificationContent
    ) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        let hour = profile.reminderHour
        let minute = profile.reminderMinute
        let weekdays = profile.effectiveScanWeekdays

        switch profile.cadence {
        case .daily:
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            requests.append(UNNotificationRequest(
                identifier: "\(reminderIdentifierPrefix).daily",
                content: content, trigger: trigger
            ))

        case .weekly:
            for wd in weekdays {
                var comps = DateComponents()
                comps.weekday = wd
                comps.hour = hour
                comps.minute = minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                requests.append(UNNotificationRequest(
                    identifier: "\(reminderIdentifierPrefix).weekly.\(wd)",
                    content: content, trigger: trigger
                ))
            }

        case .biweekly:
            // iOS can't schedule a true biweekly repeating trigger natively.
            // Schedule the next 12 occurrences per selected weekday at 2-week intervals.
            let cal = Calendar.current
            for wd in weekdays {
                var seed = nextWeekday(wd, hour: hour, minute: minute, from: Date())
                if profile.biweeklyOffset == 1 {
                    seed = cal.date(byAdding: .weekOfYear, value: 1, to: seed) ?? seed
                }
                for i in 0..<12 {
                    guard let fire = cal.date(byAdding: .weekOfYear, value: i * 2, to: seed) else { continue }
                    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    requests.append(UNNotificationRequest(
                        identifier: "\(reminderIdentifierPrefix).biweekly.wd\(wd).\(i)",
                        content: content, trigger: trigger
                    ))
                }
            }

        case .monthly:
            var comps = DateComponents()
            comps.day = min(28, max(1, profile.scanDayOfMonth))
            comps.hour = hour
            comps.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            requests.append(UNNotificationRequest(
                identifier: "\(reminderIdentifierPrefix).monthly",
                content: content, trigger: trigger
            ))
        }
        return requests
    }

    private static func nextWeekday(_ weekday: Int, hour: Int, minute: Int, from date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 1
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        return cal.nextDate(after: date, matching: comps, matchingPolicy: .nextTime) ?? date
    }

    // MARK: - Debug / validation

    /// Schedules a one-off test notification 5 seconds out. Useful for the user to verify delivery.
    static func sendTestNotification() {
        Task {
            let status = await authorizationStatus()
            guard status == .authorized || status == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Evolv reminder test"
            content.body = "Notifications are working. You'll receive your scan reminders on schedule."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(reminderIdentifierPrefix).test",
                content: content, trigger: trigger
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
