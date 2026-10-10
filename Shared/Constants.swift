// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Identifiers and paths shared by the main app and the privileged helper.
///
/// The bundle identifier is configured once (Config/Base.xcconfig → `BLM_BUNDLE_ID`)
/// and every other identifier is derived from it, so the app, helper,
/// launchd plist can never drift apart.
public enum BLMConstants {
    public static let helperSuffix = ".helper"

    /// Bundle identifier of the main application.
    public static let appBundleID = "top.agata.MacBDEMounter"

    /// Bundle identifier / launchd label / Mach service name of the helper.
    public static let helperBundleID = "top.agata.MacBDEMounter.helper"
    public static let machServiceName = "top.agata.MacBDEMounter.helper"
    public static let launchdPlistName = "top.agata.MacBDEMounter.helper.plist"
    public static let helperVersion = "1.3.0"

    /// Executable name of the helper inside `Contents/MacOS`.
    public static let helperExecutableName = "MacBDEMounterHelper"

    /// Identifiers used before the product was renamed from "BitLockerMounter".
    /// Only referenced to migrate / clean up older installations.
    public enum Legacy {
        public static let appBundleID = "top.agata.BitLockerMounter"
        public static let helperLabel = "top.agata.BitLockerMounter.helper"
        public static let launchdPlists = [
            "/Library/LaunchDaemons/top.agata.BitLockerMounter.helper.plist",
            "/Library/LaunchDaemons/top.agata.bitlockermounter.helper.plist",
        ]
        public static let helperTool = "/Library/PrivilegedHelperTools/top.agata.BitLockerMounter.helper"
        public static let supportRoot = "/Library/Application Support/BitLockerMounter"
        public static let appPath = "/Applications/BitLockerMounter.app"
    }

    /// os_log subsystem used by both processes.
    public static let logSubsystem = "top.agata.MacBDEMounter"

    /// Info.plist key holding the code-signing requirement of the *peer* process.
    public static let helperRequirementKey = "BLMHelperRequirement"   // read by the app
    public static let clientRequirementKey = "BLMClientRequirement"   // read by the helper

    /// Prefix of the temporary FUSE mount points (`/tmp/dislocker_<GUID>`).
    /// `/tmp` is resolved to `/private/tmp` to compare against getfsstat output.
    public static let fuseMountRoot = "/private/tmp"
    public static let fuseMountPrefix = "dislocker_"

    /// Application-owned location where the helper deploys FUSE-T's NFS server.
    public static let supportRoot = "/Library/Application Support/MacBDEMounter"
    public static var fuseTInstallDir: String { supportRoot + "/fuse-t" }
    public static var fuseTServerPath: String { fuseTInstallDir + "/bin/go-nfsv4" }

    public static func requirement(forKey key: String, in bundle: Bundle = .main) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
