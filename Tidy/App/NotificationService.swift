import AppKit
import UserNotifications

/// Local notifications only. Nothing is sent off this Mac.
enum NotificationService {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    @MainActor
    static func notifyIfInactive(title: String, body: String) {
        guard !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func scheduleReminder(_ reminder: ScanReminder) {
        let center = UNUserNotificationCenter.current()
        let id = "scan-reminder"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard reminder != .never else { return }
        var components = DateComponents()
        components.hour = 10
        switch reminder {
        case .weekly: components.weekday = 2
        case .monthly: components.day = 1
        case .never: return
        }
        let content = UNMutableNotificationContent()
        content.title = "Review your storage"
        content.body = "Scan your Mac to see what you can clean up."
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
    }
}
