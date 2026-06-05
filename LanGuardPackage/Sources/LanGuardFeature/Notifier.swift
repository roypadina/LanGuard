import Foundation
import UserNotifications

/// Thin wrapper over UNUserNotificationCenter for toggle banners.
public enum Notifier {

    /// Ask for banner permission once (no-op if already decided).
    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, error in
            if let error { NSLog("LanGuard: notification auth error: \(error)") }
        }
    }

    public static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("LanGuard: notification post error: \(error)") }
        }
    }
}
