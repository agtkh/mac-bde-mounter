// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Type-safe accessors for localized user-facing strings defined in Localizable.xcstrings.
public enum L10n {
    public static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Mac BDE Mounter"
    }

    public static func versionString(version: String, build: String) -> String {
        String(format: NSLocalizedString("app.version.format %@ %@", comment: ""), version, build)
    }

    public static let authorLabel = NSLocalizedString("app.author.label", comment: "")
    public static let authorName = NSLocalizedString("app.author.name", comment: "")

    public enum Common {
        public static let ok = NSLocalizedString("common.ok", comment: "")
        public static let cancel = NSLocalizedString("common.cancel", comment: "")
        public static let close = NSLocalizedString("common.close", comment: "")
        public static func error(_ detail: String) -> String {
            String(format: NSLocalizedString("common.error.prefix %@", comment: ""), detail)
        }
    }

    public enum Menu {
        public static let title = NSLocalizedString("menu.title", comment: "")
        public static let rescanTooltip = NSLocalizedString("menu.rescan.tooltip", comment: "")
        public static let noDrives = NSLocalizedString("menu.empty.noDrives", comment: "")
        public static let rescanButton = NSLocalizedString("menu.rescan.button", comment: "")
        public static let warningFDA = NSLocalizedString("menu.warning.fda", comment: "")
        public static let warningFDAButton = NSLocalizedString("menu.warning.fda.button", comment: "")
        public static let warningHelper = NSLocalizedString("menu.warning.helper", comment: "")
        public static let warningHelperButton = NSLocalizedString("menu.warning.helper.button", comment: "")
        public static let about = NSLocalizedString("menu.footer.about", comment: "")
        public static let setup = NSLocalizedString("menu.footer.setup", comment: "")
        public static let updates = NSLocalizedString("menu.footer.updates", comment: "")
        public static let quit = NSLocalizedString("menu.footer.quit", comment: "")
    }

    public enum DriveAction {
        public static let openInFinderTooltip = NSLocalizedString("drive.action.openInFinder.tooltip", comment: "")
        public static let eject = NSLocalizedString("drive.action.eject", comment: "")
        public static let unlock = NSLocalizedString("drive.action.unlock", comment: "")
    }

    public enum Status {
        public static let locked = NSLocalizedString("status.locked", comment: "")
        public static let unlocking = NSLocalizedString("status.unlocking", comment: "")
        public static let mounting = NSLocalizedString("status.mounting", comment: "")
        public static let mounted = NSLocalizedString("status.mounted", comment: "")
        public static let unmounting = NSLocalizedString("status.unmounting", comment: "")
        public static func unlockFailed(_ detail: String) -> String {
            String(format: NSLocalizedString("status.unlockFailed %@", comment: ""), detail)
        }
        public static let mountFailed = NSLocalizedString("status.mountFailed", comment: "")
    }

    public enum Prompt {
        public static let title = NSLocalizedString("prompt.title", comment: "")
        public static func message(_ name: String) -> String {
            String(format: NSLocalizedString("prompt.message %@", comment: ""), name)
        }
        public static let placeholder = NSLocalizedString("prompt.placeholder", comment: "")
        public static let unlock = NSLocalizedString("prompt.unlock", comment: "")
        public static let cancel = NSLocalizedString("prompt.cancel", comment: "")
    }

    public enum Notification {
        public static func mountedTitle(_ name: String) -> String {
            String(format: NSLocalizedString("notification.mounted.title %@", comment: ""), name)
        }
        public static let mountedBody = NSLocalizedString("notification.mounted.body", comment: "")
    }

    public enum Onboarding {
        public static let windowTitle = NSLocalizedString("onboarding.window.title", comment: "")
        public static let title = NSLocalizedString("onboarding.title", comment: "")
        public static let description = NSLocalizedString("onboarding.description", comment: "")
        public static let fdaTitle = NSLocalizedString("onboarding.fda.title", comment: "")
        public static let fdaDescription = NSLocalizedString("onboarding.fda.description", comment: "")
        public static let fdaButton = NSLocalizedString("onboarding.fda.button", comment: "")
        public static let fdaRestartNotice = NSLocalizedString("onboarding.fda.restartNotice", comment: "")
        public static let fdaRelaunchButton = NSLocalizedString("onboarding.fda.relaunchButton", comment: "")
        public static let helperTitle = NSLocalizedString("onboarding.helper.title", comment: "")
        public static let helperDescription = NSLocalizedString("onboarding.helper.description", comment: "")
        public static let helperInstall = NSLocalizedString("onboarding.helper.install", comment: "")
        public static let helperReinstall = NSLocalizedString("onboarding.helper.reinstall", comment: "")
        public static func helperFDATitle(_ name: String) -> String {
            String(format: NSLocalizedString("onboarding.helper.fda.title %@", comment: ""), name)
        }
        public static let helperFDADescription = NSLocalizedString("onboarding.helper.fda.description", comment: "")
        public static let helperFDARevealButton = NSLocalizedString("onboarding.helper.fda.revealButton", comment: "")
        public static let legacyTitle = NSLocalizedString("onboarding.legacy.title", comment: "")
        public static let legacyDescription = NSLocalizedString("onboarding.legacy.description", comment: "")
        public static let legacyTrash = NSLocalizedString("onboarding.legacy.trash", comment: "")
        public static let recheck = NSLocalizedString("onboarding.footer.recheck", comment: "")
        public static let uninstall = NSLocalizedString("onboarding.footer.uninstall", comment: "")
        public static let done = NSLocalizedString("onboarding.footer.done", comment: "")
    }

    public enum About {
        public static let windowTitle = NSLocalizedString("about.window.title", comment: "")
        public static let mainLicense = NSLocalizedString("about.license.main", comment: "")
        public static let ossHeader = NSLocalizedString("about.oss.list.header", comment: "")
        public static let authorLabel = NSLocalizedString("about.author.label", comment: "")
        public static let repoLink = NSLocalizedString("about.repository.link", comment: "")
        public static let licenseLabel = NSLocalizedString("about.license.label", comment: "")
        public static let noticeLabel = NSLocalizedString("about.notice.label", comment: "")
        public static let trademarkTitle = NSLocalizedString("about.trademark.title", comment: "")
        public static let trademarkBody = NSLocalizedString("about.trademark.body", comment: "")
        public static let viewLicense = NSLocalizedString("about.button.license", comment: "")
        public static let viewNotices = NSLocalizedString("about.button.notices", comment: "")
        public static let uninstall = NSLocalizedString("about.button.uninstall", comment: "")
        public static let close = NSLocalizedString("about.button.close", comment: "")
        public static func notFound(_ name: String) -> String {
            String(format: NSLocalizedString("about.notFound.alert %@", comment: ""), name)
        }
    }

    public enum OSSPurpose {
        public static let dislocker = NSLocalizedString("oss.dislocker.purpose", comment: "")
        public static let fuset = NSLocalizedString("oss.fuset.purpose", comment: "")
        public static let mbedtls = NSLocalizedString("oss.mbedtls.purpose", comment: "")
        public static let sparkle = NSLocalizedString("oss.sparkle.purpose", comment: "")
    }

    public enum Uninstaller {
        public static let confirmTitle = NSLocalizedString("uninstaller.confirm.title", comment: "")
        public static let confirmBody = NSLocalizedString("uninstaller.confirm.body", comment: "")
        public static let confirmAction = NSLocalizedString("uninstaller.confirm.action", comment: "")
        public static let confirmTerminal = NSLocalizedString("uninstaller.confirm.terminal", comment: "")
        public static let confirmCancel = NSLocalizedString("uninstaller.confirm.cancel", comment: "")
        public static let notFoundTitle = NSLocalizedString("uninstaller.notFound.title", comment: "")
        public static let notFoundBody = NSLocalizedString("uninstaller.notFound.body", comment: "")
        public static let successTitle = NSLocalizedString("uninstaller.success.title", comment: "")
        public static let successBody = NSLocalizedString("uninstaller.success.body", comment: "")
        public static let failedTitle = NSLocalizedString("uninstaller.failed.title", comment: "")
        public static func failedBody(_ error: String) -> String {
            String(format: NSLocalizedString("uninstaller.failed.body %@", comment: ""), error)
        }
        public static let launchFailedTitle = NSLocalizedString("uninstaller.launchFailed.title", comment: "")
    }
}
