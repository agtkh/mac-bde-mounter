// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import UserNotifications
import AppKit
import os.log

public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()
    private let logger = Logger(subsystem: BLMConstants.logSubsystem, category: "notifications")

    private override init() {
        super.init()
    }

    public func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                self.logger.warning("Notification authorization error: \(error.localizedDescription, privacy: .public)")
            } else {
                self.logger.info("Notification authorization granted: \(granted)")
            }
        }
    }

    public func postMountedNotification(volumeName: String, mountPath: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.Notification.mountedTitle(volumeName)
        content.body = L10n.Notification.mountedBody
        content.sound = .default
        content.userInfo = ["mountPath": mountPath]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "mounted_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Failed to post mounted notification: \(error.localizedDescription, privacy: .public)")
            } else {
                self.logger.info("Posted mounted notification for \(volumeName, privacy: .public) at \(mountPath, privacy: .public)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Present notification even when the menu app is in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 14.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    // Open mount path in Finder when user clicks the notification
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let mountPath = response.notification.request.content.userInfo["mountPath"] as? String {
            logger.info("User clicked mount notification, opening: \(mountPath, privacy: .public)")
            DispatchQueue.main.async {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountPath)
            }
        }
        completionHandler()
    }
}
