// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest
@testable import MacBDEMounter

final class BitLockerHeaderTests: XCTestCase {
    func testClassicBitLockerHeaderDetection() {
        var sector = Data(repeating: 0, count: 512)

        // Set signature "-FVE-FS-" at offset 3
        let sig = Data("-FVE-FS-".utf8)
        sector.replaceSubrange(3..<11, with: sig)

        // Set test GUID at offset 0xA0:
        let rawGUID: [UInt8] = [
            0x12, 0x34, 0x56, 0x78,
            0xAB, 0xCD,
            0xEF, 0x01,
            0x23, 0x45,
            0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x01
        ]
        sector.replaceSubrange(0xA0..<0xA0 + 16, with: rawGUID)

        // Set metadata offset 1 at 0xB0 (e.g. 0x0000000002100000)
        var offset1 = UInt64(0x02100000).littleEndian
        let offData = Data(bytes: &offset1, count: 8)
        sector.replaceSubrange(0xB0..<0xB8, with: offData)

        let result = BitLockerHeader.probe(sector: sector)
        XCTAssertTrue(result.isBitLocker)
        XCTAssertFalse(result.isBitLockerToGo)
        XCTAssertEqual(result.volumeGUID, "78563412-CDAB-01EF-2345-6789ABCDEF01")
        XCTAssertEqual(result.metadataOffsets, [0x02100000])
    }

    func testBitLockerToGoHeaderDetection() {
        var sector = Data(repeating: 0, count: 512)

        // Set signature "MSWIN4.1" at offset 3
        let sig = Data("MSWIN4.1".utf8)
        sector.replaceSubrange(3..<11, with: sig)

        let rawGUID: [UInt8] = [
            0xAA, 0xBB, 0xCC, 0xDD,
            0x11, 0x22,
            0x33, 0x44,
            0x55, 0x66,
            0x77, 0x88, 0x99, 0x00, 0xAA, 0xBB
        ]
        sector.replaceSubrange(0x1A8..<0x1A8 + 16, with: rawGUID)

        // Set metadata offset at 0x1B8
        var offset1 = UInt64(0x01000000).littleEndian
        let offData = Data(bytes: &offset1, count: 8)
        sector.replaceSubrange(0x1B8..<0x1C0, with: offData)

        let result = BitLockerHeader.probe(sector: sector)
        XCTAssertTrue(result.isBitLocker)
        XCTAssertTrue(result.isBitLockerToGo)
        XCTAssertEqual(result.volumeGUID, "DDCCBBAA-2211-4433-5566-77889900AABB")
        XCTAssertEqual(result.metadataOffsets, [0x01000000])
    }

    func testBootSectorLabelExtraction() {
        var sector = Data(repeating: 0, count: 512)
        let sig = Data("-FVE-FS-".utf8)
        sector.replaceSubrange(3..<11, with: sig)

        let labelString = "USB-PRIVATE"
        let labelData = Data(labelString.utf8)
        sector.replaceSubrange(0x47..<0x47 + labelData.count, with: labelData)

        let result = BitLockerHeader.probe(sector: sector)
        XCTAssertTrue(result.isBitLocker)
        XCTAssertEqual(result.bootSectorLabel, "USB-PRIVATE")
        XCTAssertEqual(result.volumeLabel, "USB-PRIVATE")
    }

    func testExtractVolumeLabelVariousFormats() {
        // Standard Windows BitLocker format: <ComputerName> <VolumeLabel> <Date>
        XCTAssertEqual(
            BitLockerHeader.extractVolumeLabel(fromDescription: "DESKTOP-ABC USB-PRIVATE 2026-10-10"),
            "USB-PRIVATE"
        )
        // Multi-word volume label
        XCTAssertEqual(
            BitLockerHeader.extractVolumeLabel(fromDescription: "MYPC BDE TEST 8/5/2011"),
            "BDE TEST"
        )
        // Slash date format
        XCTAssertEqual(
            BitLockerHeader.extractVolumeLabel(fromDescription: "LAPTOP-XYZ USB-PRIVATE 10/10/2026"),
            "USB-PRIVATE"
        )
        // Bare volume label
        XCTAssertEqual(
            BitLockerHeader.extractVolumeLabel(fromDescription: "USB-PRIVATE"),
            "USB-PRIVATE"
        )
        // Multi-word description without date
        XCTAssertEqual(
            BitLockerHeader.extractVolumeLabel(fromDescription: "Encrypted Secure Storage"),
            "Encrypted Secure Storage"
        )
        // Only computer and date (no volume label)
        XCTAssertEqual(
            BitLockerHeader.extractVolumeLabel(fromDescription: "DESKTOP-ABC 2026-10-10"),
            ""
        )
    }

    func testParseMetadataBlockWithDescription() {
        var block = Data(repeating: 0, count: 4096)

        // Offset 0: Signature "-FVE-FS-"
        block.replaceSubrange(0..<8, with: Data("-FVE-FS-".utf8))

        // Offset 8: size (UInt16 LE) = 0x0100 (256 * 16 = 4096 bytes)
        var sizeVal = UInt16(0x0100).littleEndian
        block.replaceSubrange(8..<10, with: Data(bytes: &sizeVal, count: 2))

        // Offset 10: version (UInt16 LE) = 2
        var versionVal = UInt16(2).littleEndian
        block.replaceSubrange(10..<12, with: Data(bytes: &versionVal, count: 2))

        // Offset 0x40: dataset header (header_size = 0x30, dataset_size = 0x200)
        var datasetSize = UInt32(0x0200).littleEndian
        block.replaceSubrange(0x40..<0x44, with: Data(bytes: &datasetSize, count: 4))
        var headerSize = UInt32(0x30).littleEndian
        block.replaceSubrange(0x48..<0x4C, with: Data(bytes: &headerSize, count: 4))

        // Datums begin at 0x40 + 0x30 = 0x70
        let descString = "DESKTOP-ABC USB-PRIVATE 2026-10-10\0"
        let descUtf16 = descString.data(using: .utf16LittleEndian)!
        let datumTotalSize = UInt16(8 + descUtf16.count)

        var dSize = datumTotalSize.littleEndian
        var dEntry = UInt16(0x0007).littleEndian // Description
        var dVal = UInt16(0x0002).littleEndian   // Unicode string
        var dErr = UInt16(0).littleEndian

        block.replaceSubrange(0x70..<0x72, with: Data(bytes: &dSize, count: 2))
        block.replaceSubrange(0x72..<0x74, with: Data(bytes: &dEntry, count: 2))
        block.replaceSubrange(0x74..<0x76, with: Data(bytes: &dVal, count: 2))
        block.replaceSubrange(0x76..<0x78, with: Data(bytes: &dErr, count: 2))
        block.replaceSubrange(0x78..<0x78 + descUtf16.count, with: descUtf16)

        let parsedLabel = BitLockerHeader.parseMetadataBlock(data: block)
        XCTAssertEqual(parsedLabel, "USB-PRIVATE")
    }

    func testNonBitLockerSector() {
        let emptySector = Data(repeating: 0, count: 512)
        let result = BitLockerHeader.probe(sector: emptySector)
        XCTAssertFalse(result.isBitLocker)
        XCTAssertNil(result.volumeGUID)
        XCTAssertNil(result.volumeLabel)
    }

    func testFormatMixedEndianGUID() {
        let raw: [UInt8] = [
            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06,
            0x07, 0x08,
            0x09, 0x0A,
            0x0B, 0x0C,
            0x0D, 0x0E, 0x0F, 0x10
        ]
        let formatted = BitLockerHeader.formatMixedEndianGUID(Data(raw))
        XCTAssertEqual(formatted, "04030201-0605-0807-090A-0B0C0D0E0F10")
    }
}
