// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation

public enum PasswordPrompt {
    private static var isPrompting = false

    /// Displays a synchronous modal dialog to prompt for BitLocker password.
    public static func prompt(
        bsdName: String,
        volumeName: String
    ) -> SecureBytes? {
        assert(Thread.isMainThread, "Password prompt must be shown on the main thread")
        guard !isPrompting else { return nil }
        isPrompting = true
        defer { isPrompting = false }

        let alert = NSAlert()
        let displayName = volumeName.isEmpty ? bsdName : "\(volumeName) (\(bsdName))"
        alert.messageText = L10n.Prompt.title
        alert.informativeText = L10n.Prompt.message(displayName)
        alert.alertStyle = .informational

        alert.addButton(withTitle: L10n.Prompt.unlock)
        alert.addButton(withTitle: L10n.Prompt.cancel)

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = L10n.Prompt.placeholder

        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.window.level = .floating
        alert.window.center()

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let passStr = input.stringValue
            guard !passStr.isEmpty else { return nil }
            let sec = SecureBytes(string: passStr)
            input.stringValue = "" // Clear field memory
            return sec
        }

        return nil
    }
}
