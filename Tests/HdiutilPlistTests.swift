// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest
@testable import MacBDEMounter

final class HdiutilPlistTests: XCTestCase {
    func testParseHDIUtilAttachOutput() {
        let sampleXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>system-entities</key>
            <array>
                <dict>
                    <key>content-hint</key>
                    <string>Apple_partition_scheme</string>
                    <key>dev-entry</key>
                    <string>/dev/disk7</string>
                </dict>
                <dict>
                    <key>content-hint</key>
                    <string>Microsoft Basic Data</string>
                    <key>dev-entry</key>
                    <string>/dev/disk7s1</string>
                </dict>
            </array>
        </dict>
        </plist>
        """

        let data = Data(sampleXML.utf8)
        let bsd = MountSessionManager.parseHDIUtilAttachOutput(data: data)
        XCTAssertEqual(bsd, "disk7s1")
    }

    func testParseBareDiskEntity() {
        let sampleXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>system-entities</key>
            <array>
                <dict>
                    <key>dev-entry</key>
                    <string>/dev/disk8</string>
                </dict>
            </array>
        </dict>
        </plist>
        """

        let data = Data(sampleXML.utf8)
        let bsd = MountSessionManager.parseHDIUtilAttachOutput(data: data)
        XCTAssertEqual(bsd, "disk8")
    }

    func testParseInvalidData() {
        let data = Data("not a plist".utf8)
        let bsd = MountSessionManager.parseHDIUtilAttachOutput(data: data)
        XCTAssertNil(bsd)
    }
}
