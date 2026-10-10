// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import os.log

public final class MountSessionManager {
    public static let shared = MountSessionManager()
    private let logger = Logger(subsystem: BLMConstants.logSubsystem, category: "mount-session")

    public struct Session {
        public let bsdName: String
        public let volumeGUID: String
        public let fuseMountPoint: String
        public var imageBSDName: String
        public var dislockerProcess: Process?
    }

    private var sessions: [String: Session] = [:]
    private let lock = NSLock()

    private init() {}

    private func findBundledDislocker() -> URL? {
        if let execURL = Bundle.main.executableURL {
            let candidate = execURL.deletingLastPathComponent().appendingPathComponent("bin/dislocker")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        if let resURL = Bundle.main.resourceURL?.appendingPathComponent("bin/dislocker"),
           FileManager.default.isExecutableFile(atPath: resURL.path) {
            return resURL
        }
        let appCandidate = URL(fileURLWithPath: "/Applications/MacBDEMounter.app/Contents/MacOS/bin/dislocker")
        if FileManager.default.isExecutableFile(atPath: appCandidate.path) {
            return appCandidate
        }
        let supportCandidate = URL(fileURLWithPath: "/Library/Application Support/MacBDEMounter/bin/dislocker")
        if FileManager.default.isExecutableFile(atPath: supportCandidate.path) {
            return supportCandidate
        }
        return nil
    }

    private func reapProcess(_ process: Process) {
        guard process.isRunning else {
            process.waitUntilExit()
            return
        }
        process.terminate()
        let killDeadline = Date().addingTimeInterval(1.0)
        while process.isRunning && Date() < killDeadline {
            usleep(20_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    /// Unlocks a BitLocker drive and returns the attached image BSD name (e.g. "disk7s1").
    public func unlock(
        bsdName: String,
        volumeGUID: String,
        password: Data
    ) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        guard Validation.isValidBSDName(bsdName) else {
            throw BLMHelperError.make(.invalidArgument, description: "Invalid BSD name: \(bsdName)")
        }
        guard Validation.isValidVolumeGUID(volumeGUID) else {
            throw BLMHelperError.make(.invalidArgument, description: "Invalid volume GUID: \(volumeGUID)")
        }
        guard let mountPoint = Validation.fuseMountPoint(forGUID: volumeGUID) else {
            throw BLMHelperError.make(.invalidArgument, description: "Invalid mount point for GUID")
        }

        // If a session already exists for this volume, verify its device node still exists
        if let existing = sessions[volumeGUID], !existing.imageBSDName.isEmpty {
            if FileManager.default.fileExists(atPath: "/dev/\(existing.imageBSDName)") {
                return existing.imageBSDName
            }
        }

        // Clean up any stale mounts, dangling disk images, or orphaned dislocker/go-nfsv4 processes
        cleanupVolume(volumeGUID: volumeGUID, mountPoint: mountPoint)

        // Ensure FUSE-T is present
        try FuseTInstaller.ensureInstalled()

        guard let dislockerURL = findBundledDislocker() else {
            logger.error("dislocker binary not found in bundle")
            throw BLMHelperError.make(.general, description: "dislocker binary missing from app bundle")
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: mountPoint) {
            try fm.createDirectory(atPath: mountPoint, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }

        // Convert password data to string
        guard let passwordStr = String(data: password, encoding: .utf8) else {
            throw BLMHelperError.make(.invalidArgument, description: "Password could not be decoded as UTF-8")
        }

        let dislockerFile = (mountPoint as NSString).appendingPathComponent("dislocker-file")

        // Prefer raw character device (/dev/rdisk...) for maximum throughput and compatibility
        let devPath = fm.fileExists(atPath: "/dev/r\(bsdName)") ? "/dev/r\(bsdName)" : "/dev/\(bsdName)"
        let logFile = "/tmp/blm-dislocker-\(volumeGUID).log"
        try? fm.removeItem(atPath: logFile)

        // Start dislocker with -o nobrowse to hide intermediate FUSE/NFS mount from Finder
        let process = Process()
        process.executableURL = dislockerURL
        process.arguments = [
            "-v",
            "-l", logFile,
            "-V", devPath,
            "-u\(passwordStr)",
            "--",
            "-s",
            "-o", "nobrowse",
            mountPoint
        ]

        var env = ProcessInfo.processInfo.environment
        env["FUSE_NFSSRV_PATH"] = BLMConstants.fuseTServerPath
        let binDir = dislockerURL.deletingLastPathComponent().path
        if let existingDyld = env["DYLD_LIBRARY_PATH"], !existingDyld.isEmpty {
            env["DYLD_LIBRARY_PATH"] = "\(binDir):\(existingDyld)"
        } else {
            env["DYLD_LIBRARY_PATH"] = binDir
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            logger.error("Failed to start dislocker: \(error.localizedDescription, privacy: .public)")
            try? fm.removeItem(atPath: mountPoint)
            throw BLMHelperError.make(.toolFailed, description: "Failed to spawn dislocker: \(error.localizedDescription)")
        }

        // Wait up to 30 seconds for dislocker-file to appear.
        // Note: Dislocker daemonizes upon successful initialization, so the parent process
        // exits with status 0 while the background process serves the FUSE mount.
        let deadline = Date().addingTimeInterval(30.0)
        var fileAppeared = false

        while Date() < deadline {
            if fm.fileExists(atPath: dislockerFile) {
                fileAppeared = true
                break
            }
            if !process.isRunning && process.terminationStatus != 0 {
                // Dislocker exited with a non-zero exit code (failure)
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        if !fileAppeared {
            var errorDetails = ""
            if let logData = try? Data(contentsOf: URL(fileURLWithPath: logFile)),
               let logString = String(data: logData, encoding: .utf8), !logString.isEmpty {
                errorDetails = logString
            } else {
                let errData = errPipe.fileHandleForReading.availableData
                let outData = outPipe.fileHandleForReading.availableData
                let combined = (String(data: errData, encoding: .utf8) ?? "") + (String(data: outData, encoding: .utf8) ?? "")
                errorDetails = combined
            }
            try? fm.removeItem(atPath: logFile)

            cleanupVolume(volumeGUID: volumeGUID, mountPoint: mountPoint)

            logger.error("dislocker exited or timed out without creating virtual file. Output: \(errorDetails, privacy: .public)")
            let trimmed = errorDetails.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.localizedCaseInsensitiveContains("password") ||
               trimmed.localizedCaseInsensitiveContains("login") ||
               trimmed.localizedCaseInsensitiveContains("auth") ||
               trimmed.localizedCaseInsensitiveContains("cannot decrypt") ||
               trimmed.localizedCaseInsensitiveContains("can't decrypt") {
                throw BLMHelperError.make(.authFailed, description: "BitLocker authentication failed (invalid password)")
            } else {
                let statusMsg = process.isRunning ? "timed out waiting for dislocker-file" : "exit code \(process.terminationStatus)"
                let desc = trimmed.isEmpty ? statusMsg : trimmed
                throw BLMHelperError.make(.toolFailed, description: "dislocker failed: \(desc)")
            }
        }

        // Attach virtual disk image with hdiutil
        let attachRes = ProcessRunner.run(
            executable: "/usr/bin/hdiutil",
            arguments: [
                "attach",
                "-plist",
                "-nomount",
                "-noverify",
                "-imagekey", "diskimage-class=CRawDiskImage",
                dislockerFile
            ],
            timeout: 30.0
        )

        guard attachRes.isSuccess else {
            logger.error("hdiutil attach failed: \(attachRes.stderrString, privacy: .public)")
            cleanupVolume(volumeGUID: volumeGUID, mountPoint: mountPoint)
            throw BLMHelperError.make(.toolFailed, description: "hdiutil attach failed: \(attachRes.stderrString)")
        }

        guard let imageBSD = parseHDIUtilAttachOutput(data: attachRes.stdoutData) else {
            logger.error("Could not parse BSD device from hdiutil output")
            cleanupVolume(volumeGUID: volumeGUID, mountPoint: mountPoint)
            throw BLMHelperError.make(.toolFailed, description: "Failed to parse attached disk name")
        }

        let session = Session(
            bsdName: bsdName,
            volumeGUID: volumeGUID,
            fuseMountPoint: mountPoint,
            imageBSDName: imageBSD,
            dislockerProcess: process
        )
        sessions[volumeGUID] = session

        logger.info("Successfully unlocked \(bsdName, privacy: .public) as \(imageBSD, privacy: .public) at \(mountPoint, privacy: .public)")
        return imageBSD
    }

    /// Robustly tears down any processes, hdiutil attachments, and NFS mounts for a given volume GUID.
    public func cleanupVolume(volumeGUID: String, mountPoint: String) {
        logger.info("Cleaning up volume session for GUID: \(volumeGUID, privacy: .public)")

        // 1. Detach any attached hdiutil disk images that reference this mount point or GUID
        let infoRes = ProcessRunner.run(executable: "/usr/bin/hdiutil", arguments: ["info", "-plist"], timeout: 5.0)
        if infoRes.isSuccess,
           let plist = try? PropertyListSerialization.propertyList(from: infoRes.stdoutData, format: nil) as? [String: Any],
           let images = plist["images"] as? [[String: Any]] {
            for image in images {
                let imgPath = image["image-path"] as? String ?? ""
                if imgPath.contains(volumeGUID) || imgPath.contains(mountPoint) {
                    if let entities = image["system-entities"] as? [[String: Any]] {
                        for entity in entities {
                            if let devEntry = entity["dev-entry"] as? String {
                                _ = ProcessRunner.run(executable: "/usr/sbin/diskutil", arguments: ["unmount", "force", devEntry], timeout: 5.0)
                                _ = ProcessRunner.run(executable: "/usr/bin/hdiutil", arguments: ["detach", devEntry, "-force"], timeout: 10.0)
                            }
                        }
                    }
                }
            }
        }

        // Also detach by session imageBSDName if recorded
        if let session = sessions[volumeGUID], !session.imageBSDName.isEmpty {
            _ = ProcessRunner.run(executable: "/usr/sbin/diskutil", arguments: ["unmount", "force", "/dev/\(session.imageBSDName)"], timeout: 5.0)
            _ = ProcessRunner.run(executable: "/usr/bin/hdiutil", arguments: ["detach", "/dev/\(session.imageBSDName)", "-force"], timeout: 10.0)
        }

        // 2. Unmount FUSE/NFS mount point forcefully (loop to handle stacked mounts)
        for _ in 0..<5 {
            let umountRes = ProcessRunner.run(executable: "/sbin/umount", arguments: ["-f", mountPoint], timeout: 5.0)
            if !umountRes.isSuccess {
                break
            }
        }

        // 3. Kill any lingering dislocker or go-nfsv4 processes for this volume
        _ = ProcessRunner.run(executable: "/usr/bin/pkill", arguments: ["-9", "-f", "dislocker.*\(volumeGUID)"], timeout: 3.0)
        _ = ProcessRunner.run(executable: "/usr/bin/pkill", arguments: ["-9", "-f", "go-nfsv4.*\(volumeGUID)"], timeout: 3.0)

        if let proc = sessions[volumeGUID]?.dislockerProcess {
            reapProcess(proc)
        }

        // 4. Clean up directories and logs
        try? FileManager.default.removeItem(atPath: mountPoint)
        try? FileManager.default.removeItem(atPath: "/tmp/blm-dislocker-\(volumeGUID).log")

        sessions.removeValue(forKey: volumeGUID)
    }

    /// Dismounts and detaches a session.
    public func teardown(volumeGUID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard Validation.isValidVolumeGUID(volumeGUID) else {
            throw BLMHelperError.make(.invalidArgument, description: "Invalid volume GUID: \(volumeGUID)")
        }

        let mountPoint = Validation.fuseMountPoint(forGUID: volumeGUID) ?? "\(BLMConstants.fuseMountRoot)/\(BLMConstants.fuseMountPrefix)\(volumeGUID)"
        cleanupVolume(volumeGUID: volumeGUID, mountPoint: mountPoint)
        logger.info("Successfully tore down session for \(volumeGUID, privacy: .public)")
    }

    /// Returns list of active sessions.
    public func activeSessionInfo() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }

        return sessions.values.map { session in
            [
                "bsdName": session.bsdName,
                "volumeGUID": session.volumeGUID,
                "fuseMountPoint": session.fuseMountPoint,
                "imageBSDName": session.imageBSDName
            ]
        }
    }

    /// Parses the XML plist output of `hdiutil attach -plist`.
    public static func parseHDIUtilAttachOutput(data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            return nil
        }

        // Prefer partition entity (e.g. disk7s1) over bare disk entry (disk7)
        var partitionBSD: String? = nil
        var wholeDiskBSD: String? = nil

        for entity in entities {
            guard let devEntry = entity["dev-entry"] as? String else { continue }
            let bsd = devEntry.replacingOccurrences(of: "/dev/", with: "")
            if bsd.contains("s") {
                partitionBSD = bsd
            } else if wholeDiskBSD == nil {
                wholeDiskBSD = bsd
            }
        }

        return partitionBSD ?? wholeDiskBSD
    }

    private func parseHDIUtilAttachOutput(data: Data) -> String? {
        return MountSessionManager.parseHDIUtilAttachOutput(data: data)
    }
}
