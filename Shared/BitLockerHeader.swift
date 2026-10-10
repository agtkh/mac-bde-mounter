// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Pure logic parser for BitLocker volume header signatures, Volume GUID, and partition label.
public enum BitLockerHeader {
    public static let signatureFVE = Data("-FVE-FS-".utf8)
    public static let signatureMSWIN = Data("MSWIN4.1".utf8)

    public struct ProbeResult: Equatable {
        public let isBitLocker: Bool
        public let volumeGUID: String?
        public let isBitLockerToGo: Bool
        public let volumeLabel: String?
        public let metadataOffsets: [UInt64]
        public let bootSectorLabel: String?

        public init(
            isBitLocker: Bool,
            volumeGUID: String? = nil,
            isBitLockerToGo: Bool = false,
            volumeLabel: String? = nil,
            metadataOffsets: [UInt64] = [],
            bootSectorLabel: String? = nil
        ) {
            self.isBitLocker = isBitLocker
            self.volumeGUID = volumeGUID
            self.isBitLockerToGo = isBitLockerToGo
            self.volumeLabel = volumeLabel
            self.metadataOffsets = metadataOffsets
            self.bootSectorLabel = bootSectorLabel
        }
    }

    /// Parses the first sector (512 bytes) of a volume partition.
    public static func probe(sector: Data) -> ProbeResult {
        guard sector.count >= 512 else {
            return ProbeResult(isBitLocker: false)
        }

        let sigAt3 = sector.subdata(in: 3..<11)
        let hasFVEAt3 = (sigAt3 == signatureFVE)
        let hasMSWINAt3 = (sigAt3 == signatureMSWIN)

        let hasFVEAt52: Bool
        if sector.count >= 0x52 + 8 {
            hasFVEAt52 = (sector.subdata(in: 0x52..<0x52 + 8) == signatureFVE)
        } else {
            hasFVEAt52 = false
        }

        let bootSectorLabel = extractBootSectorLabel(sector: sector)

        if hasFVEAt3 {
            // Classic BitLocker (NTFS format)
            var guidString: String? = nil
            if sector.count >= 0xA0 + 16 {
                let guidBytes = sector.subdata(in: 0xA0..<0xA0 + 16)
                if !isAllZero(guidBytes) {
                    guidString = formatMixedEndianGUID(guidBytes)
                }
            }

            var offsets: [UInt64] = []
            for off in [0xB0, 0xB8, 0xC0] {
                let val = readUInt64LE(from: sector, offset: off)
                if val > 0 && !offsets.contains(val) {
                    offsets.append(val)
                }
            }
            // Vista fallback if information_off is 0
            if offsets.isEmpty {
                let vistaLcn = readUInt64LE(from: sector, offset: 0x38)
                let spc = UInt64(sector[0xD])
                let bytesPerSec = UInt64(readUInt16LE(from: sector, offset: 0xB))
                if vistaLcn > 0 && spc > 0 && bytesPerSec > 0 {
                    offsets.append(vistaLcn * spc * bytesPerSec)
                }
            }

            return ProbeResult(
                isBitLocker: true,
                volumeGUID: guidString,
                isBitLockerToGo: false,
                volumeLabel: bootSectorLabel,
                metadataOffsets: offsets,
                bootSectorLabel: bootSectorLabel
            )
        } else if hasMSWINAt3 || hasFVEAt52 {
            // BitLocker-To-Go (FAT / exFAT format)
            var guidString: String? = nil
            if sector.count >= 0x1A8 + 16 {
                let guidBytes = sector.subdata(in: 0x1A8..<0x1A8 + 16)
                if !isAllZero(guidBytes) {
                    guidString = formatMixedEndianGUID(guidBytes)
                }
            }

            var offsets: [UInt64] = []
            for off in [0x1B8, 0x1C0, 0x1C8] {
                let val = readUInt64LE(from: sector, offset: off)
                if val > 0 && !offsets.contains(val) {
                    offsets.append(val)
                }
            }

            return ProbeResult(
                isBitLocker: true,
                volumeGUID: guidString,
                isBitLockerToGo: true,
                volumeLabel: bootSectorLabel,
                metadataOffsets: offsets,
                bootSectorLabel: bootSectorLabel
            )
        }

        return ProbeResult(isBitLocker: false)
    }

    /// Extracts the 11-byte volume label from sector 0 (offset 0x47 / 71).
    public static func extractBootSectorLabel(sector: Data) -> String? {
        guard sector.count >= 0x47 + 11 else { return nil }
        let labelData = sector.subdata(in: 0x47..<0x47 + 11)
        guard let asciiStr = String(data: labelData, encoding: .ascii) else { return nil }
        let trimmed = asciiStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != "NO NAME",
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0.isPunctuation || $0 == " " || $0 == "-" || $0 == "_") }) else {
            return nil
        }
        return trimmed
    }

    /// Parses an FVE metadata block to extract the volume label (datum 0x0007 / Unicode).
    public static func parseMetadataBlock(data: Data) -> String? {
        guard data.count >= 0x70 else { return nil }
        guard data.subdata(in: 0..<8) == signatureFVE else { return nil }

        let sizeRaw = readUInt16LE(from: data, offset: 8)
        let version = readUInt16LE(from: data, offset: 10)

        let totalSize: Int = (version == 2) ? (Int(sizeRaw) << 4) : Int(sizeRaw)
        let blockLimit = min(data.count, max(totalSize, 0x70))

        guard blockLimit >= 0x40 + 0x30 else { return nil }
        let datasetSize = readUInt32LE(from: data, offset: 0x40)
        let headerSize = readUInt32LE(from: data, offset: 0x48)

        guard headerSize >= 0x30, datasetSize >= headerSize else { return nil }

        var datumOffset = 0x40 + Int(headerSize)
        let datasetEnd = min(blockLimit, 0x40 + Int(datasetSize))

        while datumOffset + 8 <= datasetEnd {
            let datumSize = Int(readUInt16LE(from: data, offset: datumOffset))
            let entryType = readUInt16LE(from: data, offset: datumOffset + 2)
            let valueType = readUInt16LE(from: data, offset: datumOffset + 4)

            guard datumSize >= 8, datumOffset + datumSize <= datasetEnd else {
                break
            }

            // Entry 0x0007: Description (Drive label)
            // Value 0x0002: Unicode string (UTF-16LE)
            if entryType == 0x0007 && valueType == 0x0002 {
                let payloadData = data.subdata(in: (datumOffset + 8)..<(datumOffset + datumSize))
                if let utf16Str = String(data: payloadData, encoding: .utf16LittleEndian) {
                    let cleaned = utf16Str.trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                    if !cleaned.isEmpty {
                        let label = extractVolumeLabel(fromDescription: cleaned)
                        if !label.isEmpty {
                            return label
                        }
                    }
                }
            }

            datumOffset += datumSize
        }

        return nil
    }

    /// Extracts the partition volume label from a BitLocker description string.
    /// BitLocker format: "<ComputerName> <VolumeLabel> <Date>"
    /// e.g. "DESKTOP-123 USB-PRIVATE 2026-10-10" -> "USB-PRIVATE"
    /// e.g. "MYPC BDE TEST 8/5/2011" -> "BDE TEST"
    /// e.g. "USB-PRIVATE" -> "USB-PRIVATE"
    public static func extractVolumeLabel(fromDescription description: String) -> String {
        let cleaned = description.trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
        guard !cleaned.isEmpty else { return "" }

        let tokens = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if tokens.count == 1 {
            return tokens[0]
        }

        let datePattern = #"^\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}$"#
        let lastToken = tokens[tokens.count - 1]
        let isDate = (lastToken.range(of: datePattern, options: .regularExpression) != nil)

        if isDate {
            if tokens.count >= 3 {
                let labelTokens = tokens[1..<(tokens.count - 1)]
                return labelTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            } else {
                return ""
            }
        }

        return cleaned
    }

    public static func readUInt16LE(from data: Data, offset: Int) -> UInt16 {
        guard data.count >= offset + 2 else { return 0 }
        return data.subdata(in: offset..<offset + 2).withUnsafeBytes {
            $0.loadUnaligned(as: UInt16.self).littleEndian
        }
    }

    public static func readUInt32LE(from data: Data, offset: Int) -> UInt32 {
        guard data.count >= offset + 4 else { return 0 }
        return data.subdata(in: offset..<offset + 4).withUnsafeBytes {
            $0.loadUnaligned(as: UInt32.self).littleEndian
        }
    }

    public static func readUInt64LE(from data: Data, offset: Int) -> UInt64 {
        guard data.count >= offset + 8 else { return 0 }
        return data.subdata(in: offset..<offset + 8).withUnsafeBytes {
            $0.loadUnaligned(as: UInt64.self).littleEndian
        }
    }

    private static func isAllZero(_ data: Data) -> Bool {
        return data.allSatisfy { $0 == 0 }
    }

    /// Converts 16 raw GUID bytes in Microsoft mixed-endian format to canonical UUID string:
    /// - bytes 0..3: little endian
    /// - bytes 4..5: little endian
    /// - bytes 6..7: little endian
    /// - bytes 8..9: big endian
    /// - bytes 10..15: big endian
    public static func formatMixedEndianGUID(_ data: Data) -> String? {
        guard data.count == 16 else { return nil }
        let b = [UInt8](data)

        let part1 = String(format: "%02X%02X%02X%02X", b[3], b[2], b[1], b[0])
        let part2 = String(format: "%02X%02X", b[5], b[4])
        let part3 = String(format: "%02X%02X", b[7], b[6])
        let part4 = String(format: "%02X%02X", b[8], b[9])
        let part5 = String(format: "%02X%02X%02X%02X%02X%02X", b[10], b[11], b[12], b[13], b[14], b[15])

        return "\(part1)-\(part2)-\(part3)-\(part4)-\(part5)"
    }
}
