// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Foundation
import os.log

public enum Permissions {
    private static let logger = Logger(subsystem: BLMConstants.logSubsystem, category: "permissions")

    /// Tests if the process has Full Disk Access by trying to read protected paths.
    public static var hasFullDiskAccess: Bool {
        let homeDir = NSHomeDirectory()
        let fm = FileManager.default

        // Test 1: User TCC.db
        let tccPath = (homeDir as NSString).appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        let fd = open(tccPath, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return true
        }

        // Test 2: Standard TCC-protected directories
        for dirName in ["Library/Safari", "Library/Mail", "Library/Messages", "Library/Suggestions"] {
            let dirPath = (homeDir as NSString).appendingPathComponent(dirName)
            if fm.fileExists(atPath: dirPath) {
                if let _ = try? fm.contentsOfDirectory(atPath: dirPath) {
                    return true
                }
            }
        }

        return false
    }

    /// Opens System Settings directly to Privacy & Security -> Full Disk Access.
    public static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Reveals the privileged helper binary in Finder so the user can drag it into Full Disk Access.
    public static func revealHelperInFinder() {
        let helperPath = "/Library/PrivilegedHelperTools/\(BLMConstants.machServiceName)"
        let url = URL(fileURLWithPath: helperPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
