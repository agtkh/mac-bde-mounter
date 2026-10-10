// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import os.log

public enum DeviceProbe {
    private static let logger = Logger(subsystem: BLMConstants.logSubsystem, category: "device-probe")

    /// Reads the first sector of a BSD disk (e.g. "disk4s1") and inspects it for BitLocker headers,
    /// followed by parsing the metadata blocks to extract the volume label.
    public static func probe(bsdName: String) -> BitLockerHeader.ProbeResult {
        guard Validation.isValidBSDName(bsdName) else {
            logger.error("Invalid BSD name supplied to probe: \(bsdName, privacy: .public)")
            return BitLockerHeader.ProbeResult(isBitLocker: false)
        }

        // Try raw disk device first (/dev/rdisk...), then block device (/dev/disk...)
        let rawPath = "/dev/r\(bsdName)"
        let blockPath = "/dev/\(bsdName)"

        var probeRes: BitLockerHeader.ProbeResult? = nil
        var activePath: String = rawPath

        if let data = readFirstSector(path: rawPath) {
            probeRes = BitLockerHeader.probe(sector: data)
            activePath = rawPath
            logger.info("Probe on raw \(rawPath, privacy: .public): isBitLocker=\(probeRes!.isBitLocker), GUID=\(probeRes!.volumeGUID ?? "none", privacy: .public)")
        } else if let data = readFirstSector(path: blockPath) {
            probeRes = BitLockerHeader.probe(sector: data)
            activePath = blockPath
            logger.info("Probe on block \(blockPath, privacy: .public): isBitLocker=\(probeRes!.isBitLocker), GUID=\(probeRes!.volumeGUID ?? "none", privacy: .public)")
        }

        guard let res = probeRes, res.isBitLocker else {
            logger.warning("Could not read BitLocker header on device \(bsdName, privacy: .public)")
            return BitLockerHeader.ProbeResult(isBitLocker: false)
        }

        // Attempt to extract the volume label from metadata blocks
        var label: String? = nil
        for offset in res.metadataOffsets {
            if let metaData = readBytes(path: activePath, offset: off_t(offset), count: 65536) ??
                              readBytes(path: (activePath == rawPath ? blockPath : rawPath), offset: off_t(offset), count: 65536) {
                if let extracted = BitLockerHeader.parseMetadataBlock(data: metaData) {
                    label = extracted
                    logger.info("Found volume label in metadata offset 0x\(String(offset, radix: 16), privacy: .public): \(extracted, privacy: .public)")
                    break
                }
            }
        }

        let finalLabel = label ?? res.bootSectorLabel
        logger.info("Probe final result for \(bsdName, privacy: .public): label=\(finalLabel ?? "none", privacy: .public)")

        return BitLockerHeader.ProbeResult(
            isBitLocker: true,
            volumeGUID: res.volumeGUID,
            isBitLockerToGo: res.isBitLockerToGo,
            volumeLabel: finalLabel,
            metadataOffsets: res.metadataOffsets,
            bootSectorLabel: res.bootSectorLabel
        )
    }

    /// Checks whether the helper process has Full Disk Access (FDA) by attempting to open /dev/rdisk0.
    public static func hasFullDiskAccess() -> Bool {
        let fd = open("/dev/rdisk0", O_RDONLY)
        if fd >= 0 {
            close(fd)
            return true
        }
        let err = errno
        logger.info("FDA probe on /dev/rdisk0: errno=\(err) (\(String(cString: strerror(err)), privacy: .public))")
        if err == EPERM {
            return false
        }
        // If device node doesn't exist, try /dev/disk0
        let bfd = open("/dev/disk0", O_RDONLY)
        if bfd >= 0 {
            close(bfd)
            return true
        }
        let berr = errno
        logger.info("FDA probe on /dev/disk0: errno=\(berr) (\(String(cString: strerror(berr)), privacy: .public))")
        return berr != EPERM
    }

    private static func readFirstSector(path: String) -> Data? {
        readBytes(path: path, offset: 0, count: 4096)
    }

    private static func readBytes(path: String, offset: off_t, count: Int) -> Data? {
        let fd = open(path, O_RDONLY)
        if fd < 0 {
            let err = errno
            logger.warning("open(\(path, privacy: .public)) failed: errno=\(err) (\(String(cString: strerror(err)), privacy: .public))")
            return nil
        }
        defer { close(fd) }

        var rawPtr: UnsafeMutableRawPointer? = nil
        let alignRet = posix_memalign(&rawPtr, 4096, count)
        guard alignRet == 0, let buffer = rawPtr else {
            logger.warning("posix_memalign failed for \(path, privacy: .public)")
            return nil
        }
        defer { free(buffer) }

        let bytesRead = pread(fd, buffer, count, offset)
        if bytesRead < 512 {
            let err = errno
            logger.warning("pread(\(path, privacy: .public), offset=\(offset)) failed: bytesRead=\(bytesRead), errno=\(err) (\(String(cString: strerror(err)), privacy: .public))")
            return nil
        }

        return Data(bytes: buffer, count: bytesRead)
    }
}
