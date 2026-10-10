// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Sparkle

public final class AppUpdater: ObservableObject {
    public static let shared = AppUpdater()

    public var isConfigured: Bool {
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURL.isEmpty,
              let pubKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !pubKey.isEmpty else {
            return false
        }
        return true
    }

    private lazy var updaterController: SPUStandardUpdaterController? = {
        guard isConfigured else { return nil }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    private init() {}

    public func checkForUpdates() {
        guard let controller = updaterController else { return }
        controller.checkForUpdates(nil)
    }
}
