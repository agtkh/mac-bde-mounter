// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import DiskArbitration
import Foundation
import os.log

public final class DiskMonitor {
    public static let shared = DiskMonitor()
    private let logger = Logger(subsystem: BLMConstants.logSubsystem, category: "disk-monitor")

    private var daSession: DASession?
    private var claimedDisks: [String: DADisk] = [:]
    private var physicalToVirtual: [String: String] = [:] // bsdName -> imageBSD
    private var virtualToGUID: [String: String] = [:]     // imageBSD -> volumeGUID
    private var promptedBSDNames: Set<String> = []

    private init() {}

    public func start() {
        guard daSession == nil else { return }

        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            logger.error("Failed to create DiskArbitration session")
            return
        }

        self.daSession = session
        DASessionSetDispatchQueue(session, DispatchQueue.main)

        let context = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskAppearedCallback(session, nil, { (disk, ctx) in
            guard let ctx = ctx else { return }
            let monitor = Unmanaged<DiskMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.handleDiskAppeared(disk: disk)
        }, context)

        DARegisterDiskDisappearedCallback(session, nil, { (disk, ctx) in
            guard let ctx = ctx else { return }
            let monitor = Unmanaged<DiskMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.handleDiskDisappeared(disk: disk)
        }, context)

        DARegisterDiskDescriptionChangedCallback(session, nil, nil, { (disk, keys, ctx) in
            guard let ctx = ctx else { return }
            let monitor = Unmanaged<DiskMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.handleDiskDescriptionChanged(disk: disk)
        }, context)

        logger.info("DiskArbitration monitor started")
        scanConnectedDrives()
    }

    public func scanConnectedDrives() {
        guard let session = daSession else { return }
        logger.info("Scanning currently connected external disks...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["list", "-plist", "external"]
            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let allDisks = plist["AllDisksAndPartitions"] as? [[String: Any]] else {
                    return
                }

                for diskEntry in allDisks {
                    if let partitions = diskEntry["Partitions"] as? [[String: Any]] {
                        for part in partitions {
                            if let bsdName = part["DeviceIdentifier"] as? String {
                                let mountPoint = part["MountPoint"] as? String
                                if mountPoint != nil && !mountPoint!.isEmpty {
                                    continue
                                }
                                // Skip if already claimed, already mapped to virtual disk, or already mounted
                                if self.claimedDisks[bsdName] != nil ||
                                   self.physicalToVirtual[bsdName] != nil ||
                                   DriveStore.shared.drive(forBSD: bsdName)?.isMounted == true {
                                    continue
                                }
                                DispatchQueue.main.async {
                                    if let daDisk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) {
                                        if let desc = DADiskCopyDescription(daDisk) as? [String: Any] {
                                            self.claimDisk(disk: daDisk, bsdName: bsdName, desc: desc)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                self.logger.error("Failed to run diskutil list: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func stop() {
        if let session = daSession {
            DASessionSetDispatchQueue(session, nil)
            daSession = nil
        }
    }

    // MARK: - Disk Events

    private func handleDiskAppeared(disk: DADisk) {
        guard let desc = DADiskCopyDescription(disk) as? [String: Any] else { return }

        // Only process external block devices
        let isInternal = desc[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? false
        let isMediaWhole = desc[kDADiskDescriptionMediaWholeKey as String] as? Bool ?? false
        guard !isInternal else { return }

        guard let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String else { return }

        // If this is an attached virtual image from dislocker (e.g. disk7s1), mount it
        if let guid = virtualToGUID[bsdName] {
            logger.info("Virtual decrypted disk appeared: \(bsdName, privacy: .public) for GUID \(guid, privacy: .public)")
            mountVirtualDisk(disk: disk, bsdName: bsdName, guid: guid)
            return
        }

        // For partitions on physical drives, claim to prevent OS "Initialize..." prompt
        if !isMediaWhole && bsdName.contains("s") {
            claimDisk(disk: disk, bsdName: bsdName, desc: desc)
        }
    }

    private func handleDiskDisappeared(disk: DADisk) {
        guard let desc = DADiskCopyDescription(disk) as? [String: Any],
              let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String else {
            return
        }

        logger.info("Disk disappeared: \(bsdName, privacy: .public)")

        // If virtual disk disappeared, tear down the FUSE session
        if let guid = virtualToGUID.removeValue(forKey: bsdName) {
            HelperClient.shared.teardown(volumeGUID: guid) { _ in }
            if let physicalBSD = physicalToVirtual.first(where: { $0.value == bsdName })?.key {
                physicalToVirtual.removeValue(forKey: physicalBSD)
                if var drive = DriveStore.shared.drive(forBSD: physicalBSD) {
                    drive.isMounted = false
                    drive.mountPath = nil
                    drive.imageBSDName = nil
                    drive.statusMessage = L10n.Status.locked
                    DriveStore.shared.updateDrive(drive)
                }
            }
            return
        }

        // If physical disk was unplugged, clean up
        let matchingPhysicals = physicalToVirtual.keys.filter { $0 == bsdName || (!bsdName.contains("s") && $0.starts(with: bsdName)) }
        for pBSD in matchingPhysicals {
            if let virtualBSD = physicalToVirtual.removeValue(forKey: pBSD),
               let guid = virtualToGUID.removeValue(forKey: virtualBSD) {
                HelperClient.shared.teardown(volumeGUID: guid) { _ in }
            }
            DriveStore.shared.removeDrive(bsdName: pBSD)
        }

        claimedDisks.removeValue(forKey: bsdName)
        promptedBSDNames.remove(bsdName)
        if !bsdName.contains("s") {
            // Whole disk unplugged (e.g. disk6 removed, clear disk6s1, disk6s2, etc.)
            promptedBSDNames = promptedBSDNames.filter { !$0.starts(with: bsdName) }
            for pBSD in claimedDisks.keys.filter({ $0.starts(with: bsdName) }) {
                claimedDisks.removeValue(forKey: pBSD)
            }
        }
        DriveStore.shared.removeDrive(bsdName: bsdName)
    }

    private func handleDiskDescriptionChanged(disk: DADisk) {
        guard let desc = DADiskCopyDescription(disk) as? [String: Any],
              let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String else {
            return
        }

        // Update mount path if virtual disk is mounted
        if let mountURL = desc[kDADiskDescriptionVolumePathKey as String] as? URL {
            for (physicalBSD, vBSD) in physicalToVirtual where vBSD == bsdName {
                if var drive = DriveStore.shared.drive(forBSD: physicalBSD) {
                    drive.isProcessing = false
                    drive.isMounted = true
                    drive.mountPath = mountURL.path
                    drive.statusMessage = L10n.Status.mounted
                    DriveStore.shared.updateDrive(drive)
                }
            }
        }
    }

    // MARK: - Claim & Probe

    private func claimDisk(disk: DADisk, bsdName: String, desc: [String: Any]) {
        let volumeKind = desc[kDADiskDescriptionVolumeKindKey as String] as? String
        // If macOS already recognized a filesystem (e.g. standard APFS/HFS+), do not claim
        if let vk = volumeKind, !vk.isEmpty {
            return
        }

        logger.info("Claiming candidate disk: \(bsdName, privacy: .public)")
        claimedDisks[bsdName] = disk

        let context = Unmanaged.passUnretained(self).toOpaque()

        DADiskClaim(
            disk,
            DADiskClaimOptions(kDADiskClaimOptionDefault),
            { (disk, ctx) -> Unmanaged<DADissenter>? in
                // Release callback: reject release while we are handling it
                let dissenter = DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnBusy), "Claimed by MacBDEMounter" as CFString)
                return Unmanaged.passRetained(dissenter)
            },
            context,
            { (disk, dissenter, ctx) in
                guard let ctx = ctx else { return }
                let monitor = Unmanaged<DiskMonitor>.fromOpaque(ctx).takeUnretainedValue()
                monitor.didClaimDisk(disk: disk, dissenter: dissenter)
            },
            context
        )
    }

    private func didClaimDisk(disk: DADisk, dissenter: DADissenter?) {
        guard let desc = DADiskCopyDescription(disk) as? [String: Any],
              let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String else {
            return
        }

        if let dissenter = dissenter {
            let status = DADissenterGetStatus(dissenter)
            logger.warning("Claim was dissented for \(bsdName, privacy: .public), status=\(status)")
            claimedDisks.removeValue(forKey: bsdName)
            probeAndUnlockIfBitLocker(disk: disk, bsdName: bsdName, desc: desc)
            return
        }

        logger.info("Claim successful for \(bsdName, privacy: .public), initiating probe")
        probeAndUnlockIfBitLocker(disk: disk, bsdName: bsdName, desc: desc)
    }

    private func probeAndUnlockIfBitLocker(disk: DADisk, bsdName: String, desc: [String: Any]) {
        let mediaName = desc[kDADiskDescriptionMediaNameKey as String] as? String ?? "BitLocker Drive"
        let sizeBytes = desc[kDADiskDescriptionMediaSizeKey as String] as? UInt64 ?? 0

        HelperClient.shared.probe(bsdName: bsdName) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let info):
                let isBitLocker = info["isBitLocker"] as? Bool ?? false
                let guid = info["volumeGUID"] as? String ?? ""
                let isToGo = info["isBitLockerToGo"] as? Bool ?? false

                if isBitLocker {
                    let probeLabel = (info["volumeLabel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let effectiveLabel: String
                    if let l = probeLabel, !l.isEmpty {
                        effectiveLabel = l
                    } else if !mediaName.isEmpty && mediaName != "BitLocker Drive" && mediaName != "Basic data partition" {
                        effectiveLabel = mediaName
                    } else {
                        effectiveLabel = bsdName
                    }

                    self.logger.info("Device \(bsdName, privacy: .public) IS BitLocker (GUID=\(guid, privacy: .public), label=\(effectiveLabel, privacy: .public))")

                    // Check if this volume is already unlocked/mounted (e.g. from prior session or app restart)
                    HelperClient.shared.activeSessions { [weak self] sessionRes in
                        DispatchQueue.main.async {
                            guard let self = self else { return }

                            var isAlreadyMounted = false
                            var existingImageBSD: String? = nil
                            var existingMountPath: String? = nil

                            if case .success(let sessions) = sessionRes {
                                if let sess = sessions.first(where: { ($0["volumeGUID"] as? String) == guid }),
                                   let imgBSD = sess["imageBSDName"] as? String {
                                    existingImageBSD = imgBSD
                                    self.physicalToVirtual[bsdName] = imgBSD
                                    self.virtualToGUID[imgBSD] = guid
                                    if let mp = DiskMonitor.getMountPoint(forBSD: imgBSD) ?? DiskMonitor.getMountPoint(forBSD: "\(imgBSD)s1") {
                                        existingMountPath = mp
                                        isAlreadyMounted = true
                                    }
                                }
                            }

                            // Also check if any mounted volume matches this label
                            if !isAlreadyMounted && !effectiveLabel.isEmpty && effectiveLabel != bsdName {
                                let volPath = "/Volumes/\(effectiveLabel)"
                                if FileManager.default.fileExists(atPath: volPath) {
                                    for candidate in 1...20 {
                                        let candBSD = "disk\(candidate)"
                                        if let mp = DiskMonitor.getMountPoint(forBSD: candBSD), mp == volPath {
                                            existingImageBSD = candBSD
                                            existingMountPath = mp
                                            isAlreadyMounted = true
                                            self.physicalToVirtual[bsdName] = candBSD
                                            self.virtualToGUID[candBSD] = guid
                                            break
                                        }
                                    }
                                }
                            }

                            let drive = BitLockerDrive(
                                id: bsdName,
                                volumeGUID: guid,
                                volumeName: effectiveLabel,
                                sizeBytes: sizeBytes,
                                isBitLocker: true,
                                isBitLockerToGo: isToGo,
                                isMounted: isAlreadyMounted,
                                mountPath: existingMountPath,
                                imageBSDName: existingImageBSD,
                                statusMessage: isAlreadyMounted ? L10n.Status.mounted : L10n.Status.locked,
                                isProcessing: false
                            )
                            DriveStore.shared.updateDrive(drive)

                            // Automatically prompt for password only if not already mounted
                            if !isAlreadyMounted &&
                               !self.promptedBSDNames.contains(bsdName) &&
                               self.physicalToVirtual[bsdName] == nil {
                                self.promptedBSDNames.insert(bsdName)
                                self.unlockFlow(
                                    bsdName: bsdName,
                                    volumeName: effectiveLabel,
                                    guid: guid
                                )
                            }
                        }
                    }
                } else {
                    if !DriveStore.shared.isHelperFDAAuthorized {
                        self.logger.warning("Device \(bsdName, privacy: .public) probe returned false, but helper daemon lacks Full Disk Access!")
                        DriveStore.shared.refreshPermissions()
                    }
                    self.logger.info("Device \(bsdName, privacy: .public) is not BitLocker, unclaiming")
                    self.unclaimDisk(disk: disk, bsdName: bsdName)
                }

            case .failure(let error):
                self.logger.error("Probe failed for \(bsdName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                self.unclaimDisk(disk: disk, bsdName: bsdName)
            }
        }
    }

    private func unclaimDisk(disk: DADisk, bsdName: String) {
        DADiskUnclaim(disk)
        claimedDisks.removeValue(forKey: bsdName)
    }

    // MARK: - Unlock Flow

    public func unlockFlow(bsdName: String, volumeName: String, guid: String) {
        // Show password prompt on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let password = PasswordPrompt.prompt(bsdName: bsdName, volumeName: volumeName) else {
                if var drive = DriveStore.shared.drive(forBSD: bsdName) {
                    drive.statusMessage = L10n.Status.locked
                    drive.isProcessing = false
                    DriveStore.shared.updateDrive(drive)
                }
                return
            }

            self.performUnlock(
                bsdName: bsdName,
                guid: guid,
                password: password
            )
        }
    }

    // MARK: - Mount Utilities

    public static func getMountPoint(forBSD bsd: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = ["info", "-plist", bsd]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        if let mounted = plist["Mounted"] as? Bool, mounted,
           let mp = plist["MountPoint"] as? String, !mp.isEmpty {
            return mp
        }
        return nil
    }

    private func performUnlock(
        bsdName: String,
        guid: String,
        password: SecureBytes
    ) {
        if var drive = DriveStore.shared.drive(forBSD: bsdName) {
            drive.isProcessing = true
            drive.statusMessage = L10n.Status.unlocking
            DriveStore.shared.updateDrive(drive)
        }

        HelperClient.shared.unlock(bsdName: bsdName, volumeGUID: guid, password: password) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                switch result {
                case .success(let imageBSD):
                    self.logger.info("Unlock successful for \(bsdName, privacy: .public) -> \(imageBSD, privacy: .public)")

                    self.physicalToVirtual[bsdName] = imageBSD
                    self.virtualToGUID[imageBSD] = guid

                    if var drive = DriveStore.shared.drive(forBSD: bsdName) {
                        drive.imageBSDName = imageBSD
                        drive.statusMessage = L10n.Status.mounting
                        DriveStore.shared.updateDrive(drive)
                    }

                    // 1. Check if macOS already auto-mounted this virtual disk upon attach
                    if let session = self.daSession {
                        for candidateBSD in [imageBSD, "\(imageBSD)s1", "\(imageBSD)s2"] {
                            if let d = DADiskCreateFromBSDName(kCFAllocatorDefault, session, candidateBSD),
                               let desc = DADiskCopyDescription(d) as? [String: Any],
                               let mountURL = desc[kDADiskDescriptionVolumePathKey as String] as? URL {
                                self.logger.info("Virtual disk \(candidateBSD, privacy: .public) is already mounted by OS at \(mountURL.path, privacy: .public)")
                                self.handleMountedDisk(vBSD: imageBSD, mountURL: mountURL)
                                return
                            }
                        }
                    }

                    // 2. Check diskutil info in case DA hasn't updated its cache yet
                    if let mp = DiskMonitor.getMountPoint(forBSD: imageBSD) ?? DiskMonitor.getMountPoint(forBSD: "\(imageBSD)s1") {
                        self.logger.info("Virtual disk \(imageBSD, privacy: .public) is already mounted according to diskutil at \(mp, privacy: .public)")
                        self.handleMountedDisk(vBSD: imageBSD, mountURL: URL(fileURLWithPath: mp))
                        return
                    }

                    // 3. Otherwise explicitly mount
                    self.mountVirtualDisk(bsdName: imageBSD, guid: guid)

                case .failure(let error):
                    let localizedErr = HelperErrorLocalization.localizedDescription(for: error as NSError)
                    self.logger.error("Unlock failed for \(bsdName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    if var drive = DriveStore.shared.drive(forBSD: bsdName) {
                        drive.isProcessing = false
                        drive.statusMessage = L10n.Status.unlockFailed(localizedErr)
                        DriveStore.shared.updateDrive(drive)
                    }

                    let alert = NSAlert()
                    alert.messageText = L10n.Status.unlockFailed(bsdName)
                    alert.informativeText = localizedErr
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Mount & Unmount Virtual Disk

    private func mountVirtualDisk(bsdName: String, guid: String) {
        guard let session = daSession,
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            return
        }
        mountVirtualDisk(disk: disk, bsdName: bsdName, guid: guid)
    }

    private func mountVirtualDisk(disk: DADisk, bsdName: String, guid: String) {
        guard daSession != nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()

        DADiskMount(
            disk,
            nil,
            DADiskMountOptions(kDADiskMountOptionDefault),
            { (disk, dissenter, ctx) in
                guard let ctx = ctx else { return }
                let monitor = Unmanaged<DiskMonitor>.fromOpaque(ctx).takeUnretainedValue()
                monitor.didMountVirtualDisk(disk: disk, dissenter: dissenter)
            },
            context
        )
    }

    private func didMountVirtualDisk(disk: DADisk, dissenter: DADissenter?) {
        guard let desc = DADiskCopyDescription(disk) as? [String: Any],
              let vBSD = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String else {
            return
        }

        if let dissenter = dissenter {
            let status = DADissenterGetStatus(dissenter)
            logger.warning("DADiskMount dissented for virtual disk \(vBSD, privacy: .public), status=\(status). Trying diskutil fallback...")

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let p1 = Process()
                p1.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                p1.arguments = ["mount", vBSD]
                try? p1.run()
                p1.waitUntilExit()

                if p1.terminationStatus != 0 {
                    let p2 = Process()
                    p2.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                    p2.arguments = ["mount", "\(vBSD)s1"]
                    try? p2.run()
                    p2.waitUntilExit()
                }

                var foundURL: URL? = nil
                for checkBSD in [vBSD, "\(vBSD)s1"] {
                    if let mp = DiskMonitor.getMountPoint(forBSD: checkBSD) {
                        foundURL = URL(fileURLWithPath: mp)
                        break
                    }
                }

                DispatchQueue.main.async {
                    if let url = foundURL {
                        self?.handleMountedDisk(vBSD: vBSD, mountURL: url)
                    } else {
                        self?.logger.error("Mount failed for virtual disk \(vBSD, privacy: .public)")
                        if let physicalBSD = self?.physicalToVirtual.first(where: { $0.value == vBSD })?.key,
                           var drive = DriveStore.shared.drive(forBSD: physicalBSD) {
                            drive.isProcessing = false
                            drive.statusMessage = L10n.Status.mountFailed
                            DriveStore.shared.updateDrive(drive)
                        }
                    }
                }
            }
            return
        }

        if let mountURL = desc[kDADiskDescriptionVolumePathKey as String] as? URL {
            handleMountedDisk(vBSD: vBSD, mountURL: mountURL)
        } else {
            // Volume path may take a moment to be reflected in DA dictionary
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var foundURL: URL? = nil
                for _ in 0..<10 {
                    if let mp = DiskMonitor.getMountPoint(forBSD: vBSD) ?? DiskMonitor.getMountPoint(forBSD: "\(vBSD)s1") {
                        foundURL = URL(fileURLWithPath: mp)
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.2)
                }

                DispatchQueue.main.async {
                    if let url = foundURL {
                        self?.handleMountedDisk(vBSD: vBSD, mountURL: url)
                    } else {
                        if let physicalBSD = self?.physicalToVirtual.first(where: { $0.value == vBSD })?.key,
                           var drive = DriveStore.shared.drive(forBSD: physicalBSD) {
                            drive.isProcessing = false
                            drive.statusMessage = L10n.Status.mounted
                            DriveStore.shared.updateDrive(drive)
                        }
                    }
                }
            }
        }
    }

    private func handleMountedDisk(vBSD: String, mountURL: URL) {
        logger.info("Mounted virtual disk \(vBSD, privacy: .public) at \(mountURL.path, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            if let physicalBSD = self?.physicalToVirtual.first(where: { $0.value == vBSD })?.key,
               var drive = DriveStore.shared.drive(forBSD: physicalBSD) {
                drive.isProcessing = false
                drive.isMounted = true
                drive.mountPath = mountURL.path
                drive.statusMessage = L10n.Status.mounted
                let folderName = mountURL.lastPathComponent
                if !folderName.isEmpty && (drive.volumeName == drive.bsdName || drive.volumeName.isEmpty) {
                    drive.volumeName = folderName
                }
                DriveStore.shared.updateDrive(drive)

                // Notify user that the volume was successfully mounted
                NotificationManager.shared.postMountedNotification(
                    volumeName: drive.volumeName,
                    mountPath: mountURL.path
                )
            }
        }
    }

    public func unmountDrive(bsdName: String) {
        guard let imageBSD = physicalToVirtual[bsdName],
              let session = daSession,
              let vDisk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, imageBSD) else {
            return
        }

        if var drive = DriveStore.shared.drive(forBSD: bsdName) {
            drive.isProcessing = true
            drive.statusMessage = L10n.Status.unmounting
            DriveStore.shared.updateDrive(drive)
        }

        let context = Unmanaged.passUnretained(self).toOpaque()

        DADiskUnmount(
            vDisk,
            DADiskUnmountOptions(kDADiskUnmountOptionDefault),
            { (disk, dissenter, ctx) in
                guard let ctx = ctx else { return }
                let monitor = Unmanaged<DiskMonitor>.fromOpaque(ctx).takeUnretainedValue()
                monitor.didUnmountVirtualDisk(disk: disk, dissenter: dissenter)
            },
            context
        )
    }

    private func didUnmountVirtualDisk(disk: DADisk, dissenter: DADissenter?) {
        guard let desc = DADiskCopyDescription(disk) as? [String: Any],
              let vBSD = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String else {
            return
        }

        if let dissenter = dissenter {
            let status = DADissenterGetStatus(dissenter)
            logger.warning("Unmount dissented for \(vBSD, privacy: .public) (status=\(status)) - device busy")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("helper.error.busy", comment: "")
                alert.informativeText = NSLocalizedString("helper.error.busy", comment: "")
                alert.alertStyle = .warning
                alert.runModal()
            }
            if let physicalBSD = physicalToVirtual.first(where: { $0.value == vBSD })?.key,
               var drive = DriveStore.shared.drive(forBSD: physicalBSD) {
                drive.isProcessing = false
                drive.statusMessage = L10n.Status.mounted
                DriveStore.shared.updateDrive(drive)
            }
            return
        }

        logger.info("Unmount completed for \(vBSD, privacy: .public), tearing down helper session")
        if let guid = virtualToGUID.removeValue(forKey: vBSD) {
            HelperClient.shared.teardown(volumeGUID: guid) { [weak self] _ in
                DispatchQueue.main.async {
                    if let physicalBSD = self?.physicalToVirtual.first(where: { $0.value == vBSD })?.key {
                        self?.physicalToVirtual.removeValue(forKey: physicalBSD)
                        if var drive = DriveStore.shared.drive(forBSD: physicalBSD) {
                            drive.isProcessing = false
                            drive.isMounted = false
                            drive.mountPath = nil
                            drive.imageBSDName = nil
                            drive.statusMessage = L10n.Status.locked
                            DriveStore.shared.updateDrive(drive)
                        }
                    }
                }
            }
        }
    }
}
