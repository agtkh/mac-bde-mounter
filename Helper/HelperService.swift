// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import os.log

public final class HelperService: NSObject, HelperProtocol {
    private let logger = Logger(subsystem: BLMConstants.logSubsystem, category: "helper-service")

    public func version(reply: @escaping (String) -> Void) {
        reply(BLMConstants.helperVersion)
    }

    public func probe(bsdName: String, reply: @escaping (NSDictionary?, NSError?) -> Void) {
        guard Validation.isValidBSDName(bsdName) else {
            reply(nil, BLMHelperError.make(.invalidArgument, description: "Invalid BSD disk name"))
            return
        }

        let result = DeviceProbe.probe(bsdName: bsdName)
        let dict: [String: Any] = [
            "isBitLocker": result.isBitLocker,
            "volumeGUID": result.volumeGUID ?? "",
            "isBitLockerToGo": result.isBitLockerToGo,
            "volumeLabel": result.volumeLabel ?? ""
        ]
        reply(dict as NSDictionary, nil)
    }

    public func checkFDA(reply: @escaping (Bool) -> Void) {
        let fda = DeviceProbe.hasFullDiskAccess()
        reply(fda)
    }

    public func ensureFuseT(reply: @escaping (NSError?) -> Void) {
        do {
            try FuseTInstaller.ensureInstalled()
            reply(nil)
        } catch let err as NSError {
            reply(err)
        } catch {
            reply(BLMHelperError.make(.general, description: error.localizedDescription))
        }
    }

    public func unlock(
        bsdName: String,
        volumeGUID: String,
        password: Data,
        reply: @escaping (String?, NSError?) -> Void
    ) {
        var mutablePassword = password
        defer {
            SecureBytes.wipe(&mutablePassword)
        }

        guard Validation.isValidBSDName(bsdName) else {
            reply(nil, BLMHelperError.make(.invalidArgument, description: "Invalid BSD device name"))
            return
        }
        guard Validation.isValidVolumeGUID(volumeGUID) else {
            reply(nil, BLMHelperError.make(.invalidArgument, description: "Invalid volume GUID"))
            return
        }

        do {
            let imageBSD = try MountSessionManager.shared.unlock(
                bsdName: bsdName,
                volumeGUID: volumeGUID,
                password: mutablePassword
            )
            reply(imageBSD, nil)
        } catch let err as NSError {
            reply(nil, err)
        } catch {
            reply(nil, BLMHelperError.make(.general, description: error.localizedDescription))
        }
    }

    public func teardown(volumeGUID: String, reply: @escaping (NSError?) -> Void) {
        guard Validation.isValidVolumeGUID(volumeGUID) else {
            reply(BLMHelperError.make(.invalidArgument, description: "Invalid volume GUID"))
            return
        }

        do {
            try MountSessionManager.shared.teardown(volumeGUID: volumeGUID)
            reply(nil)
        } catch let err as NSError {
            reply(err)
        } catch {
            reply(BLMHelperError.make(.general, description: error.localizedDescription))
        }
    }

    public func activeSessions(reply: @escaping ([NSDictionary]) -> Void) {
        let list = MountSessionManager.shared.activeSessionInfo()
        let nsArray = list.map { $0 as NSDictionary }
        reply(nsArray)
    }
}
