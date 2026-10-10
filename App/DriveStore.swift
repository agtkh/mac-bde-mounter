// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Combine

public struct BitLockerDrive: Identifiable, Equatable {
    public let id: String // BSD name, e.g. "disk4s1"
    public var bsdName: String { id }
    public var volumeGUID: String
    public var volumeName: String
    public var sizeBytes: UInt64
    public var isBitLocker: Bool
    public var isBitLockerToGo: Bool
    public var isMounted: Bool
    public var mountPath: String?
    public var imageBSDName: String?
    public var statusMessage: String
    public var isProcessing: Bool

    public static func == (lhs: BitLockerDrive, rhs: BitLockerDrive) -> Bool {
        return lhs.id == rhs.id &&
               lhs.volumeGUID == rhs.volumeGUID &&
               lhs.isMounted == rhs.isMounted &&
               lhs.statusMessage == rhs.statusMessage &&
               lhs.isProcessing == rhs.isProcessing &&
               lhs.mountPath == rhs.mountPath
    }
}

public final class DriveStore: ObservableObject {
    public static let shared = DriveStore()

    @Published public var drives: [BitLockerDrive] = []
    @Published public var isFDAAuthorized: Bool = false
    @Published public var isHelperInstalled: Bool = false
    @Published public var isHelperFDAAuthorized: Bool = false

    private init() {
        refreshPermissions()
    }

    public func refreshPermissions() {
        DispatchQueue.main.async {
            self.isFDAAuthorized = Permissions.hasFullDiskAccess
            if HelperInstaller.isEnabled {
                self.isHelperInstalled = true
            }
        }
        HelperClient.shared.version { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let ver):
                    self?.isHelperInstalled = (ver == BLMConstants.helperVersion)
                case .failure:
                    // Retry once after 0.5s in case helper is still binding its Mach port
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                        HelperClient.shared.version { retryResult in
                            DispatchQueue.main.async {
                                if case .success(let ver) = retryResult {
                                    self?.isHelperInstalled = (ver == BLMConstants.helperVersion)
                                } else {
                                    self?.isHelperInstalled = false
                                }
                            }
                        }
                    }
                }
            }
        }
        HelperClient.shared.checkFDA { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let allowed) = result {
                    self?.isHelperFDAAuthorized = allowed
                } else {
                    // Retry once after 0.5s along with version retry
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                        HelperClient.shared.checkFDA { retryResult in
                            DispatchQueue.main.async {
                                if case .success(let allowed) = retryResult {
                                    self?.isHelperFDAAuthorized = allowed
                                } else {
                                    self?.isHelperFDAAuthorized = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    public func updateDrive(_ drive: BitLockerDrive) {
        if Thread.isMainThread {
            if let idx = self.drives.firstIndex(where: { $0.id == drive.id }) {
                self.drives[idx] = drive
            } else {
                self.drives.append(drive)
            }
        } else {
            DispatchQueue.main.async {
                self.updateDrive(drive)
            }
        }
    }

    public func removeDrive(bsdName: String) {
        if Thread.isMainThread {
            self.drives.removeAll { $0.id == bsdName }
        } else {
            DispatchQueue.main.async {
                self.removeDrive(bsdName: bsdName)
            }
        }
    }

    public func drive(forBSD bsdName: String) -> BitLockerDrive? {
        return drives.first { $0.id == bsdName }
    }

    public func drive(forGUID guid: String) -> BitLockerDrive? {
        return drives.first { $0.volumeGUID == guid }
    }
}
