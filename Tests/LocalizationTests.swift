// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest
@testable import MacBDEMounter

final class LocalizationTests: XCTestCase {
    func testAppNameAndMetadata() {
        XCTAssertFalse(L10n.appName.isEmpty)
        XCTAssertEqual(L10n.appName, "Mac BDE Mounter")

        XCTAssertFalse(L10n.authorName.isEmpty)
        XCTAssertEqual(L10n.authorName, "K. Agata")

        let versionFormatted = L10n.versionString(version: "1.0.0", build: "42")
        XCTAssertTrue(versionFormatted.contains("1.0.0"))
        XCTAssertTrue(versionFormatted.contains("42"))
    }

    func testHelperErrorCodeLocalization() {
        let authDesc = HelperErrorLocalization.localizedDescription(for: .authFailed)
        XCTAssertFalse(authDesc.isEmpty)

        let busyDesc = HelperErrorLocalization.localizedDescription(for: .busy)
        XCTAssertFalse(busyDesc.isEmpty)

        let customError = BLMHelperError.make(.notBitLocker, description: "Not a bitlocker drive")
        let errorDesc = HelperErrorLocalization.localizedDescription(for: customError)
        XCTAssertFalse(errorDesc.isEmpty)

        let foreignError = NSError(domain: "foreign.domain", code: 99, userInfo: [NSLocalizedDescriptionKey: "foreign error"])
        let foreignDesc = HelperErrorLocalization.localizedDescription(for: foreignError)
        XCTAssertEqual(foreignDesc, "foreign error")
    }

    func testCatalogJSONFilesExistAndAreValid() throws {
        // Resolve path to App/Resources catalogs
        let currentFile = URL(fileURLWithPath: #filePath)
        let repoRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent()
        let localizablePath = repoRoot.appendingPathComponent("App/Resources/Localizable.xcstrings")
        let infoPlistPath = repoRoot.appendingPathComponent("App/Resources/InfoPlist.xcstrings")

        XCTAssertTrue(FileManager.default.fileExists(atPath: localizablePath.path), "Localizable.xcstrings should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistPath.path), "InfoPlist.xcstrings should exist")

        let localizableData = try Data(contentsOf: localizablePath)
        let localizableJson = try JSONSerialization.jsonObject(with: localizableData) as? [String: Any]
        XCTAssertNotNil(localizableJson)

        let strings = localizableJson?["strings"] as? [String: [String: Any]]
        XCTAssertNotNil(strings)

        // Verify key requirements
        let requiredKeys = [
            "about.trademark.title",
            "about.trademark.body",
            "menu.title",
            "menu.empty.noDrives",
            "uninstaller.confirm.title",
            "uninstaller.confirm.body"
        ]

        for key in requiredKeys {
            guard let item = strings?[key],
                  let locs = item["localizations"] as? [String: [String: Any]] else {
                XCTFail("Missing key: \(key)")
                continue
            }
            XCTAssertNotNil(locs["en"], "Missing 'en' for \(key)")
            XCTAssertNotNil(locs["ja"], "Missing 'ja' for \(key)")
        }
    }
}
