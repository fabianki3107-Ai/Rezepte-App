import Foundation
import UserNotifications

/// Lokale Benachrichtigungen für Koch-Timer (falls die App im Hintergrund ist). Keine Push-Server.
final class TimerNotificationService {
    static let shared = TimerNotificationService()

    private let center = UNUserNotificationCenter.current()

    /// Fragt die Berechtigung erst beim ersten Timer an – nicht beim App-Start (HIG: Kontext zuerst).
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func schedule(id: String, title: String, body: String, fireIn seconds: TimeInterval) async {
        guard seconds >= 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
