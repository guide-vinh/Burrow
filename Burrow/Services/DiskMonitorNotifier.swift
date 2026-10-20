import Foundation
import UserNotifications
import os

/// Local notifications for low disk space. Also the notification-center
/// delegate, so banners still show while Burrow is the frontmost app.
final class DiskMonitorNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DiskMonitorNotifier()
    private static let logger = Logger(subsystem: "fun.burrow", category: "DiskMonitorNotifier")

    /// Asks once (macOS remembers the answer) and reports whether banners
    /// may be shown.
    static func authorize() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// True when the user turned Burrow's notifications off. Never prompts.
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Posts the low-disk notification; false when it couldn't be shown
    /// (not authorized yet, or rejected), so the caller retries later.
    static func notify(_ readings: [DiskMonitorReport.Reading], threshold: Double) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Low disk space"
        content.body = readings
            .filter { $0.isLow(threshold: threshold) }
            .map { r in
                r.failed
                    ? "\(r.path): couldn't be read"
                    : "\(r.path): \(DiskMonitorReport.gb(r.free)) free (\(DiskMonitorReport.percent(r.freePercent))%)"
            }
            .joined(separator: "\n")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "fun.burrow.diskmonitor.low", content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            logger.error("Notification failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
