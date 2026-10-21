# Mac BDE Mounter

[日本語版 README (README.ja.md)](README.ja.md)

**Mac BDE Mounter** is a standalone, lightweight menu-bar utility for macOS (macOS 13 Ventura or later, Apple Silicon M1–M5) that transparently detects, unlocks, and mounts external drives formatted with Windows BitLocker® encryption (supporting exFAT, NTFS, FAT32) without requiring kernel extensions (KEXTs) or external package managers like Homebrew.

> **Trademarks & Nominative Use**:
> BitLocker® is a registered trademark of Microsoft Corporation. Mac and macOS are trademarks of Apple Inc.
> Mac BDE Mounter is an independent open-source project and is not affiliated with, endorsed by, or sponsored by Microsoft Corporation or Apple Inc. See [TRADEMARKS.md](TRADEMARKS.md) for full legal notices.

---

## Features

- **Automatic Event Detection**: Monitors USB storage connections in real-time via `DiskArbitration.framework`.
- **Interception of OS Prompts**: Claims BitLocker volumes early (`DADiskClaim`) to suppress the default macOS *"The disk you attached was not readable by this computer (Initialize...)"* dialog.
- **Keychain Integration**: Securely stores and retrieves unlock credentials by Volume GUID using macOS Keychain Services (`Security.framework`).
- **Privilege Separation**: UI and event monitoring run under user privileges, while mounting and block device access run under an isolated privileged helper daemon (`top.agata.MacBDEMounter.helper`) managed by `SMAppService`.
- **Standalone Distribution**: Bundles hermetic builds of `dislocker` (GPLv2) and the `FUSE-T` user-space filesystem driver inside the application bundle.
- **Fail-safe Unmounting**: Refuses to force unmount when files are open on the volume, prompting the user safely.
- **Menu Bar Resident UI**: SwiftUI status menu showing active BitLocker drives, real-time status (Locked, Unlocking, Mounting, Mounted), and quick action controls.
- **Full Localization (i18n)**: Native English and Japanese support out of the box, with extensible Xcode String Catalogs (`.xcstrings`).
- **Automatic Migration**: Automatically cleans up legacy `BitLockerMounter` daemon installations and notifies users if an older bundle exists.
- **Complete Uninstallation**: One-click in-app or CLI uninstaller that purges all daemons, helper tools, support directories, caches, preferences, and TCC permissions.
- **Auto-Update**: Sparkle framework integrated for automated, secure updates.

---

## Architecture

```
[External Drive Attached]
       │
       ▼
 [DiskArbitration] ──(DADiskClaim: intercept OS prompt)──► [Main App (User)]
                                                                   │
                                                 (Query Keychain / Prompt Password)
                                                                   │
                                                         [XPC Communication]
                                                                   │
                                                                   ▼
                                                       [Helper Daemon (Root)]
                                                                   │
                                                 ┌─────────────────┴─────────────────┐
                                                 ▼                                   ▼
                                        [dislocker + FUSE-T]               [hdiutil attach -nomount]
                                                 │                                   │
                                                 └─────────────────┬─────────────────┘
                                                                   ▼
                                                        [DADiskMount to /Volumes]
```

---

## Installation & Quick Start (No Build Required)

Mac BDE Mounter provides pre-built release packages (DMG). **You do NOT need to install Xcode, Homebrew, or compile the source code.**

Because this is an independent open-source project distributed without Apple's paid Developer Program certificates ($99/yr), you simply run the **initial setup tool** once after downloading to unlock macOS download security.

### 3-Step Quick Start

1. **Download the DMG**:
   Grab the latest `MacBDEMounter.dmg` from [**GitHub Releases**](https://github.com/agtkh/mac-bde-mounter/releases).
2. **Move to Applications**:
   Open `MacBDEMounter.dmg` and drag `MacBDEMounter.app` into your **Applications** folder.
3. **Run Initial Setup**:
   Double-click **`Setup.command`** in the DMG.
   > [!TIP]
   > If macOS warns that the script "cannot be opened because the developer cannot be verified", simply **right-click (or Control-click) `Setup.command` and choose "Open"**.
   >
   > **Terminal users**: You can achieve the same with a single command:
   > ```bash
   > sudo xattr -cr /Applications/MacBDEMounter.app && codesign --force --deep -s - /Applications/MacBDEMounter.app
   > ```

### First-Launch Setup

1. Launch `/Applications/MacBDEMounter.app`. Its icon will appear in your menu bar.
2. **Grant Full Disk Access**:
   Open **System Settings > Privacy & Security > Full Disk Access** and toggle **Mac BDE Mounter** on.
   *(Required to detect BitLocker volumes on connected disks without triggering macOS initialization prompts).*
3. **Approve Privileged Helper**:
   When prompted for administrator permission to set up the background mounting helper, approve via Touch ID or password.

That's it! Plug in any Windows BitLocker-encrypted external drive, and Mac BDE Mounter will automatically recognize it and present an unlock prompt.

---

## Requirements

- **Operating System**: macOS 13.0 (Ventura) or later
- **Hardware**: Apple Silicon Mac (M1 / M2 / M3 / M4 / M5)

---

## Building from Source (For Developers)

For developers who want to inspect, customize, or contribute to the project. Regular users can skip this and use the pre-built DMG above.

### Build Prerequisites
- Xcode 15 or later (or Command Line Tools + Xcode.app)
- `cmake` (`brew install cmake`)
- `xcodegen` (`brew install xcodegen`)
- Python 3 (`python3`)

The repository is fully automated for CLI workflows without requiring Xcode GUI interactions.

### 1. Build Third-Party Dependencies (dislocker, mbedTLS, FUSE-T)

```bash
make deps
```

This script:
1. Downloads and extracts the official FUSE-T distribution package (no system installation).
2. Builds static `mbedTLS 3.6.7`.
3. Builds `dislocker` (linked statically to `mbedTLS` and FUSE-T's `libfuse3.a`).
4. Stashes hermetic binaries into `vendor/dist/bin/`.

### 2. Generate Xcode Project & Build

```bash
make project   # Generates MacBDEMounter.xcodeproj via XcodeGen
make build     # Builds Debug configuration (ad-hoc signed)
```

The resulting application is staged at `build.nosync/Debug/MacBDEMounter.app`.

### 3. Run Unit Tests & Localization Checks

```bash
make test         # Runs test suite via xcodebuild
make l10n-check   # Verifies all string catalogs are 100% translated
```

### 4. Run the Application

```bash
make run
```

---

## Localization & Adding a Language

Mac BDE Mounter uses modern Xcode String Catalogs:
- [`App/Resources/Localizable.xcstrings`](App/Resources/Localizable.xcstrings): Application UI text, status messages, alerts, and notifications.
- [`App/Resources/InfoPlist.xcstrings`](App/Resources/InfoPlist.xcstrings): System bundle display names and TCC permission usage descriptions.

### Adding a New Language

1. Open `project.yml` and add the target language code (e.g., `de`, `fr`, `zh-Hans`) to `knownRegions`.
2. Edit `App/Resources/Localizable.xcstrings` and `App/Resources/InfoPlist.xcstrings` (or open in Xcode String Catalog editor) to add translations for the new locale.
3. Run `make l10n-check` to verify that all translation keys have valid values.
4. Run `make project && make test` to compile and verify.

Language selection is handled automatically by macOS based on the user's preferred language order in **System Settings > General > Language & Region**.

---

## Permissions & First Launch

On first launch, macOS requires two permissions:

1. **Full Disk Access (FDA)**:
   Navigate to **System Settings > Privacy & Security > Full Disk Access** and enable **Mac BDE Mounter**. This allows reading raw block devices (`/dev/rdisk*`) to detect BitLocker headers without triggering macOS initialization prompts.
2. **Privileged Helper Daemon**:
   The app installs its helper via `SMAppService.daemon`. If running an ad-hoc signed build for local development where `SMAppService` requires Developer ID signing, install the helper directly:
   ```bash
   make dev-install-helper
   ```
   To remove the development helper:
   ```bash
   make dev-uninstall-helper
   ```

---

## Uninstallation

To completely remove Mac BDE Mounter and all associated system services, daemon files, mount points, preferences, and permissions:

### Method 1: In-App GUI
1. Click the **Mac BDE Mounter** menu bar icon.
2. Select **About & Licenses...** (or **Setup...**).
3. Click **アンインストール... (Uninstall...)**.
4. Authorize with Touch ID or administrator password.

### Method 2: Command Line (CLI)
From the repository root:
```bash
make uninstall
# or directly:
sudo ./scripts/uninstall.sh
```

### Method 3: DMG Package
Double-click `Uninstall.command` included in the root of `MacBDEMounter.dmg`.

The uninstaller thoroughly purges:
- Active BitLocker virtual drives & mounts
- All running processes (`MacBDEMounter`, legacy `BitLockerMounter`, `dislocker`, `go-nfsv4`, helper daemons)
- Privileged Helper Daemons (`top.agata.MacBDEMounter.helper` and legacy `top.agata.BitLockerMounter.helper`)
- System application support files (`/Library/Application Support/MacBDEMounter` and legacy paths)
- Temporary files and mount points (`/tmp/blm-*`, `/private/tmp/dislocker_*`)
- User preferences, caches, and application state (`~/Library/Preferences/top.agata.MacBDEMounter*`, caches, savedState)
- Application bundles in `/Applications`
- Full Disk Access privacy permissions (`tccutil reset SystemPolicyAllFiles`)

---

## Release & Packaging

To build a signed and notarized DMG for distribution:

```bash
make CONFIG=Release IDENTITY="Developer ID Application: Your Name (TEAM_ID)" sign
make dmg
NOTARY_KEYCHAIN_PROFILE="AC_NOTARY" make notarize
```

---

## License & Trademarks

- **Author**: K. Agata
- **License**: [GNU General Public License v2.0 or later (GPL-2.0-or-later)](LICENSE)
- **Third-Party Notices**: See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details on bundled dependencies (`dislocker`, `FUSE-T`, `mbedTLS`, `Sparkle`).
- **Trademarks**: See [TRADEMARKS.md](TRADEMARKS.md) for trademark attributions and disclaimers.
