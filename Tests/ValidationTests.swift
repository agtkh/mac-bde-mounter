// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest
@testable import MacBDEMounter

final class ValidationTests: XCTestCase {
    func testValidBSDNames() {
        XCTAssertTrue(Validation.isValidBSDName("disk0"))
        XCTAssertTrue(Validation.isValidBSDName("disk4s1"))
        XCTAssertTrue(Validation.isValidBSDName("disk12s10"))

        XCTAssertFalse(Validation.isValidBSDName("/dev/disk4s1"))
        XCTAssertFalse(Validation.isValidBSDName("rdisk4s1"))
        XCTAssertFalse(Validation.isValidBSDName("disk4s1; rm -rf /"))
        XCTAssertFalse(Validation.isValidBSDName("../../dev/disk4"))
        XCTAssertFalse(Validation.isValidBSDName(""))
    }

    func testVolumeGUIDValidation() {
        XCTAssertTrue(Validation.isValidVolumeGUID("78563412-CDAB-01EF-2345-6789ABCDEF01"))
        XCTAssertTrue(Validation.isValidVolumeGUID("00000000-0000-0000-0000-000000000000"))

        // Lowercase is rejected (we enforce canonical uppercase)
        XCTAssertFalse(Validation.isValidVolumeGUID("78563412-cdab-01ef-2345-6789abcdef01"))
        XCTAssertFalse(Validation.isValidVolumeGUID("not-a-guid"))
        XCTAssertFalse(Validation.isValidVolumeGUID("78563412-CDAB-01EF-2345"))
    }

    func testFuseMountPointGenerationAndParsing() {
        let guid = "78563412-CDAB-01EF-2345-6789ABCDEF01"
        let mountPoint = Validation.fuseMountPoint(forGUID: guid)
        XCTAssertNotNil(mountPoint)
        XCTAssertEqual(mountPoint, "/private/tmp/dislocker_78563412-CDAB-01EF-2345-6789ABCDEF01")

        let parsedGUID = Validation.guid(fromFuseMountPoint: mountPoint!)
        XCTAssertEqual(parsedGUID, guid)

        let parsedFromTmp = Validation.guid(fromFuseMountPoint: "/tmp/dislocker_78563412-CDAB-01EF-2345-6789ABCDEF01")
        XCTAssertEqual(parsedFromTmp, guid)

        XCTAssertNil(Validation.guid(fromFuseMountPoint: "/tmp/other_dir"))
    }

    func testPasswordValidation() {
        let valid = Array("MySecretP@ssw0rd".utf8)
        XCTAssertTrue(Validation.isAcceptablePassword(valid))

        XCTAssertFalse(Validation.isAcceptablePassword([])) // Empty

        var withNull = valid
        withNull.append(0)
        XCTAssertFalse(Validation.isAcceptablePassword(withNull)) // Contains NUL byte
    }
}
