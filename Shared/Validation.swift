// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Strict validation of every value that crosses the XPC boundary.
/// The helper never accepts paths from the client; it only accepts
/// identifiers that pass these checks and builds paths itself.
public enum Validation {
    /// `disk4`, `disk4s1` (no `/dev/`, no `r` prefix, no other characters).
    public static func isValidBSDName(_ name: String) -> Bool {
        guard name.count <= 32 else { return false }
        return name.range(of: #"^disk[0-9]{1,4}(s[0-9]{1,4})?$"#, options: .regularExpression) != nil
    }

    /// Canonical upper-case UUID `XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`.
    public static func isValidVolumeGUID(_ guid: String) -> Bool {
        guard let uuid = UUID(uuidString: guid) else { return false }
        return uuid.uuidString == guid
    }

    /// Passwords are passed to dislocker via argv; reject NUL and enforce sane bounds.
    public static func isAcceptablePassword(_ bytes: [UInt8]) -> Bool {
        guard !bytes.isEmpty, bytes.count <= 256 else { return false }
        return !bytes.contains(0)
    }

    /// Path of the temporary FUSE mount point for a volume.
    public static func fuseMountPoint(forGUID guid: String) -> String? {
        guard isValidVolumeGUID(guid) else { return nil }
        return "\(BLMConstants.fuseMountRoot)/\(BLMConstants.fuseMountPrefix)\(guid)"
    }

    /// Reverse of `fuseMountPoint(forGUID:)`; used when recovering sessions from the mount table.
    public static func guid(fromFuseMountPoint path: String) -> String? {
        let candidates = [BLMConstants.fuseMountRoot + "/", "/tmp/"]
        for root in candidates where path.hasPrefix(root + BLMConstants.fuseMountPrefix) {
            let guid = String(path.dropFirst(root.count + BLMConstants.fuseMountPrefix.count))
            return isValidVolumeGUID(guid) ? guid : nil
        }
        return nil
    }
}
