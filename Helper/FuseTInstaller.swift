// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import CryptoKit
import os.log

public enum FuseTInstaller {
    private static let logger = Logger(subsystem: BLMConstants.logSubsystem, category: "fuset-installer")

    /// Locates the bundled fuse-t directory from the app bundle.
    private static func findBundledFuseTDir() -> URL? {
        // The helper executable is at Contents/MacOS/MacBDEMounterHelper.
        // Bundled binaries are at Contents/MacOS/bin/fuse-t.
        if let execURL = Bundle.main.executableURL {
            let candidate = execURL.deletingLastPathComponent().appendingPathComponent("bin/fuse-t")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        // Fallback: look relative to bundle resources
        if let resURL = Bundle.main.resourceURL?.appendingPathComponent("bin/fuse-t"),
           FileManager.default.fileExists(atPath: resURL.path) {
            return resURL
        }
        let appCandidate = URL(fileURLWithPath: "/Applications/MacBDEMounter.app/Contents/MacOS/bin/fuse-t")
        if FileManager.default.fileExists(atPath: appCandidate.path) {
            return appCandidate
        }
        let supportCandidate = URL(fileURLWithPath: "/Library/Application Support/MacBDEMounter/bin/fuse-t")
        if FileManager.default.fileExists(atPath: supportCandidate.path) {
            return supportCandidate
        }
        return nil
    }

    /// Verifies or installs FUSE-T into /Library/Application Support/MacBDEMounter/fuse-t.
    public static func ensureInstalled() throws {
        let destDir = URL(fileURLWithPath: BLMConstants.fuseTInstallDir)
        let destBinDir = destDir.appendingPathComponent("bin")
        let destServer = destBinDir.appendingPathComponent("go-nfsv4")
        let fm = FileManager.default

        if fm.isExecutableFile(atPath: destServer.path) {
            ensureHostsAlias()
            return
        }

        guard let bundledDir = findBundledFuseTDir() else {
            logger.error("Bundled fuse-t directory not found in application bundle")
            throw BLMHelperError.make(.fuseTMissing, description: "Bundled FUSE-T binaries missing from app bundle")
        }

        let bundledServer = bundledDir.appendingPathComponent("go-nfsv4")
        guard FileManager.default.fileExists(atPath: bundledServer.path) else {
            logger.error("Bundled go-nfsv4 binary not found at \(bundledServer.path, privacy: .public)")
            throw BLMHelperError.make(.fuseTMissing, description: "Bundled go-nfsv4 missing")
        }

        // Check if destination is already up-to-date
        var needsCopy = true
        if fm.fileExists(atPath: destServer.path) {
            do {
                let srcData = try Data(contentsOf: bundledServer)
                let dstData = try Data(contentsOf: destServer)
                let srcHash = SHA256.hash(data: srcData)
                let dstHash = SHA256.hash(data: dstData)
                if srcHash == dstHash {
                    needsCopy = false
                }
            } catch {
                needsCopy = true
            }
        }

        if needsCopy {
            logger.info("Installing FUSE-T to \(destDir.path, privacy: .public)")
            try fm.createDirectory(at: destBinDir, withIntermediateDirectories: true, attributes: [
                FileAttributeKey.posixPermissions: 0o755
            ])

            if fm.fileExists(atPath: destServer.path) {
                try fm.removeItem(at: destServer)
            }
            try fm.copyItem(at: bundledServer, to: destServer)
            try fm.setAttributes([FileAttributeKey.posixPermissions: 0o755], ofItemAtPath: destServer.path)

            let bundledLicense = Bundle.main.resourceURL?.appendingPathComponent("fuse-t/LICENSE.rtf") ?? bundledDir.appendingPathComponent("LICENSE.rtf")
            let destLicense = destDir.appendingPathComponent("LICENSE.rtf")
            if fm.fileExists(atPath: bundledLicense.path) {
                if fm.fileExists(atPath: destLicense.path) {
                    try? fm.removeItem(at: destLicense)
                }
                try? fm.copyItem(at: bundledLicense, to: destLicense)
            }
        }

        // Ensure /etc/hosts has the fuse-t loopback alias needed by FUSE-T
        ensureHostsAlias()
    }

    private static func ensureHostsAlias() {
        let hostsPath = "/etc/hosts"
        guard let content = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            logger.warning("Could not read /etc/hosts")
            return
        }

        let alias = "fuse-t"
        let ip = "127.0.0.1"

        // Look for existing entry
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: " ").map { String($0) }
            if parts.contains(ip) && parts.contains(alias) {
                return // Already present
            }
        }

        // Append alias to /etc/hosts
        let entry = "\n\(ip) \(alias)\n"
        if let handle = FileHandle(forWritingAtPath: hostsPath) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
                logger.info("Added fuse-t alias to /etc/hosts")
            }
        } else {
            logger.warning("Failed to open /etc/hosts for writing")
        }
    }
}
