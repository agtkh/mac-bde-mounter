// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Error codes returned by the privileged helper over XPC.
@objc public enum BLMHelperErrorCode: Int {
    case general = 1
    case invalidArgument = 2
    case notBitLocker = 3
    case authFailed = 4
    case fuseTMissing = 5
    case busy = 6
    case timeout = 7
    case toolFailed = 8
    case peerUntrusted = 9
}

public enum BLMHelperError {
    public static let domain = "top.agata.MacBDEMounter.helper"

    public static func make(_ code: BLMHelperErrorCode, description: String) -> NSError {
        NSError(domain: domain, code: code.rawValue, userInfo: [
            NSLocalizedDescriptionKey: description
        ])
    }
}

/// XPC protocol implemented by the privileged helper and invoked by the main app.
@objc(BLMHelperProtocol)
public protocol HelperProtocol {
    /// Returns the helper daemon version string.
    func version(reply: @escaping (String) -> Void)

    /// Inspects the given block device (e.g. "disk4s1") to check whether it contains
    /// a BitLocker header, returning metadata dictionary:
    /// ["isBitLocker": Bool, "volumeGUID": String (if available)]
    func probe(bsdName: String, reply: @escaping (NSDictionary?, NSError?) -> Void)

    /// Checks whether the helper daemon has Full Disk Access (FDA).
    func checkFDA(reply: @escaping (Bool) -> Void)

    /// Ensures that FUSE-T binaries are unpacked and installed in Application Support.
    func ensureFuseT(reply: @escaping (NSError?) -> Void)

    /// Spawns dislocker, mounts FUSE layer, attaches virtual disk image with hdiutil,
    /// and returns the attached image BSD disk name (e.g. "disk7" or "disk7s1").
    func unlock(bsdName: String, volumeGUID: String, password: Data,
                reply: @escaping (String?, NSError?) -> Void)

    /// Detaches the virtual disk image and unmounts the FUSE mount point.
    func teardown(volumeGUID: String, reply: @escaping (NSError?) -> Void)

    /// Queries all currently active unlock sessions managed by the helper daemon.
    func activeSessions(reply: @escaping ([NSDictionary]) -> Void)
}
