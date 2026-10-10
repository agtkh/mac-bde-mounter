// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import os.log

public enum AppUninstaller {
    private static let logger = Logger(subsystem: BLMConstants.logSubsystem, category: "uninstaller")

    /// Prompts the user with an NSAlert confirmation, then executes the complete uninstaller script.
    public static func confirmAndUninstall() {
        let alert = NSAlert()
        alert.messageText = L10n.Uninstaller.confirmTitle
        alert.informativeText = L10n.Uninstaller.confirmBody
        alert.alertStyle = .critical
        alert.addButton(withTitle: L10n.Uninstaller.confirmAction)
        alert.addButton(withTitle: L10n.Uninstaller.confirmTerminal)
        alert.addButton(withTitle: L10n.Uninstaller.confirmCancel)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            executeUninstallViaPrivilegedScript()
        case .alertSecondButtonReturn:
            openTerminalUninstaller()
        default:
            break
        }
    }

    /// Finds the path to the uninstall.sh script.
    public static func locateUninstallScript() -> String? {
        let fm = FileManager.default
        let bundle = Bundle.main

        // 1. In bundle resources
        if let scriptURL = bundle.url(forResource: "uninstall", withExtension: "sh"),
           fm.fileExists(atPath: scriptURL.path) {
            return scriptURL.path
        }

        let directResource = bundle.bundleURL.appendingPathComponent("Contents/Resources/uninstall.sh").path
        if fm.fileExists(atPath: directResource) {
            return directResource
        }

        // 2. Relative to bundle during development or repo build
        let devScript = bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/uninstall.sh").path
        if fm.fileExists(atPath: devScript) {
            return devScript
        }

        let repoScript = "/Users/kohei/workspace/bitlocker-mac/scripts/uninstall.sh"
        if fm.fileExists(atPath: repoScript) {
            return repoScript
        }

        return nil
    }

    private static func executeUninstallViaPrivilegedScript() {
        guard let scriptPath = locateUninstallScript() else {
            let errorAlert = NSAlert()
            errorAlert.messageText = L10n.Uninstaller.notFoundTitle
            errorAlert.informativeText = L10n.Uninstaller.notFoundBody
            errorAlert.alertStyle = .critical
            errorAlert.runModal()
            return
        }

        let bundlePath = Bundle.main.bundlePath
        logger.info("Starting uninstallation via script: \(scriptPath, privacy: .public)")

        // Execute via osascript with administrator privileges
        let shellCmd = "bash '\(scriptPath)' '\(bundlePath)' --from-app"
        let script = "do shell script \"\(shellCmd)\" with administrator privileges"

        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = ["-e", script]

        let errPipe = Pipe()
        osascript.standardError = errPipe

        do {
            try osascript.run()
            osascript.waitUntilExit()

            if osascript.terminationStatus == 0 {
                let successAlert = NSAlert()
                successAlert.messageText = L10n.Uninstaller.successTitle
                successAlert.informativeText = L10n.Uninstaller.successBody
                successAlert.alertStyle = .informational
                successAlert.addButton(withTitle: L10n.Common.ok)
                successAlert.runModal()

                NSApp.terminate(nil)
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                // User cancellation of the authorization prompt (error -60007 or -128)
                if errStr.contains("-60007") || errStr.contains("-128") || errStr.contains("User canceled") {
                    logger.info("Uninstallation was cancelled by user.")
                    return
                }

                logger.error("Uninstall script failed with code \(osascript.terminationStatus): \(errStr, privacy: .public)")
                let failAlert = NSAlert()
                failAlert.messageText = L10n.Uninstaller.failedTitle
                failAlert.informativeText = L10n.Uninstaller.failedBody(errStr)
                failAlert.alertStyle = .critical
                failAlert.runModal()
            }
        } catch {
            logger.error("Failed to launch osascript: \(error.localizedDescription, privacy: .public)")
            let failAlert = NSAlert()
            failAlert.messageText = L10n.Uninstaller.launchFailedTitle
            failAlert.informativeText = error.localizedDescription
            failAlert.alertStyle = .critical
            failAlert.runModal()
        }
    }

    private static func openTerminalUninstaller() {
        guard let scriptPath = locateUninstallScript() else {
            return
        }
        let bundlePath = Bundle.main.bundlePath
        let terminalScript = """
        tell application "Terminal"
            activate
            do script "sudo bash '\(scriptPath)' '\(bundlePath)'"
        end tell
        """

        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = ["-e", terminalScript]
        try? osascript.run()
    }
}
