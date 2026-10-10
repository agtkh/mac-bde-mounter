// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ServiceManagement
import os.log

public enum HelperInstaller {
    private static let logger = Logger(subsystem: BLMConstants.logSubsystem, category: "helper-installer")

    public static var daemonService: SMAppService {
        SMAppService.daemon(plistName: BLMConstants.launchdPlistName)
    }

    public static var status: SMAppService.Status {
        daemonService.status
    }

    public static var isEnabled: Bool {
        status == .enabled
    }

    public static func register() throws {
        let service = daemonService
        logger.info("Registering helper service: \(BLMConstants.launchdPlistName, privacy: .public)")
        do {
            try service.register()
            logger.info("Helper status after registration: \(String(describing: service.status), privacy: .public)")
            if service.status == .enabled {
                return
            }
        } catch {
            logger.warning("SMAppService register failed (\(error.localizedDescription, privacy: .public)), falling back to privileged installation")
        }

        // Clean up SMAppService registration before fallback so launchd does not conflict
        try? service.unregister()

        try installPrivilegedHelperViaScript()
    }

    public static func installPrivilegedHelperViaScript() throws {
        let fm = FileManager.default
        let bundle = Bundle.main
        var helperPath: String?

        if let url = bundle.url(forAuxiliaryExecutable: BLMConstants.helperExecutableName) {
            helperPath = url.path
        } else {
            let direct = bundle.bundleURL.appendingPathComponent("Contents/MacOS/\(BLMConstants.helperExecutableName)").path
            if fm.fileExists(atPath: direct) {
                helperPath = direct
            }
        }

        guard let sourceHelper = helperPath else {
            throw BLMHelperError.make(.general, description: "\(BLMConstants.helperExecutableName) binary not found in application bundle.")
        }

        let targetHelper = "/Library/PrivilegedHelperTools/\(BLMConstants.machServiceName)"
        let targetPlist = "/Library/LaunchDaemons/\(BLMConstants.launchdPlistName)"

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>\(BLMConstants.machServiceName)</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>\(targetHelper)</string>
        \t</array>
        \t<key>MachServices</key>
        \t<dict>
        \t\t<key>\(BLMConstants.machServiceName)</key>
        \t\t<true/>
        \t</dict>
        </dict>
        </plist>
        """

        let tempPlist = NSTemporaryDirectory() + "\(BLMConstants.launchdPlistName).tmp"
        try plistContent.write(toFile: tempPlist, atomically: true, encoding: .utf8)

        let supportRoot = BLMConstants.supportRoot
        let binSource = bundle.bundleURL.appendingPathComponent("Contents/MacOS/bin").path
        let copyBinCmd = fm.fileExists(atPath: binSource)
            ? "mkdir -p '\(supportRoot)' && cp -Rf '\(binSource)' '\(supportRoot)/' && "
            : ""

        let script = """
        \(legacyCleanupCommand()) \
        launchctl bootout system/\(BLMConstants.machServiceName) 2>/dev/null || true; \
        launchctl bootout system '\(targetPlist)' 2>/dev/null || true; \
        launchctl enable system/\(BLMConstants.machServiceName) 2>/dev/null || true; \
        mkdir -p '/Library/PrivilegedHelperTools' && \
        cp -f '\(sourceHelper)' '\(targetHelper)' && \
        chown root:wheel '\(targetHelper)' && \
        chmod 755 '\(targetHelper)' && \
        \(copyBinCmd)cp -f '\(tempPlist)' '\(targetPlist)' && \
        chown root:wheel '\(targetPlist)' && \
        chmod 644 '\(targetPlist)' && \
        launchctl enable system/\(BLMConstants.machServiceName) && \
        (launchctl bootstrap system '\(targetPlist)' 2>/dev/null || true) && \
        launchctl kickstart -kp system/\(BLMConstants.machServiceName)
        """

        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = ["-e", "do shell script \"\(script)\" with administrator privileges"]

        let errPipe = Pipe()
        osascript.standardError = errPipe

        do {
            try osascript.run()
            osascript.waitUntilExit()
            try? fm.removeItem(atPath: tempPlist)

            if osascript.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Installation cancelled or failed."
                logger.error("Privileged installation script failed: \(errStr, privacy: .public)")
                throw BLMHelperError.make(.general, description: errStr)
            }
            logger.info("Privileged helper installed via administrator prompt successfully.")
        } catch {
            try? fm.removeItem(atPath: tempPlist)
            throw error
        }
    }

    public static func unregister() throws {
        let service = daemonService
        logger.info("Unregistering helper service: \(BLMConstants.launchdPlistName, privacy: .public)")
        try? service.unregister()

        let script = """
        launchctl bootout system '/Library/LaunchDaemons/\(BLMConstants.launchdPlistName)' 2>/dev/null || true && rm -f '/Library/LaunchDaemons/\(BLMConstants.launchdPlistName)' && rm -f '/Library/PrivilegedHelperTools/\(BLMConstants.machServiceName)'
        """

        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = ["-e", "do shell script \"\(script)\" with administrator privileges"]
        try? osascript.run()
        osascript.waitUntilExit()
    }

    public static func openSystemSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    // MARK: - Migration from the pre-rename "BitLockerMounter" build

    /// Shell fragment (terminated by `;`) that stops and removes the legacy helper daemon
    /// and its support files. Every step is best-effort so a clean system is unaffected.
    static func legacyCleanupCommand() -> String {
        let legacy = BLMConstants.Legacy.self
        var parts = ["launchctl bootout system/\(legacy.helperLabel) 2>/dev/null"]
        parts += legacy.launchdPlists.map { "rm -f '\($0)'" }
        parts.append("rm -f '\(legacy.helperTool)'")
        parts.append("rm -rf '\(legacy.supportRoot)'")
        return parts.map { "\($0);" }.joined(separator: " ")
    }

    /// True when the old application bundle is still present in /Applications.
    public static var legacyAppExists: Bool {
        FileManager.default.fileExists(atPath: BLMConstants.Legacy.appPath)
    }

    /// Moves the old application bundle to the Trash (user-initiated only).
    public static func trashLegacyApp() throws {
        let url = URL(fileURLWithPath: BLMConstants.Legacy.appPath)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
