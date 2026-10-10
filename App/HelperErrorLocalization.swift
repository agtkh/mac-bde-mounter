// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

public enum HelperErrorLocalization {
    public static func localizedDescription(for code: BLMHelperErrorCode) -> String {
        switch code {
        case .general:
            return NSLocalizedString("helper.error.general", comment: "")
        case .invalidArgument:
            return NSLocalizedString("helper.error.invalidArgument", comment: "")
        case .notBitLocker:
            return NSLocalizedString("helper.error.notBitLocker", comment: "")
        case .authFailed:
            return NSLocalizedString("helper.error.authFailed", comment: "")
        case .fuseTMissing:
            return NSLocalizedString("helper.error.fuseTMissing", comment: "")
        case .busy:
            return NSLocalizedString("helper.error.busy", comment: "")
        case .timeout:
            return NSLocalizedString("helper.error.timeout", comment: "")
        case .toolFailed:
            return NSLocalizedString("helper.error.toolFailed", comment: "")
        case .peerUntrusted:
            return NSLocalizedString("helper.error.peerUntrusted", comment: "")
        }
    }

    public static func localizedDescription(for error: NSError) -> String {
        if error.domain == BLMHelperError.domain, let code = BLMHelperErrorCode(rawValue: error.code) {
            return localizedDescription(for: code)
        }
        return error.localizedDescription
    }
}
