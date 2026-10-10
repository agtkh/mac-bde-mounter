// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

public struct MenuContentView: View {
    @ObservedObject var store = DriveStore.shared
    @ObservedObject var updater = AppUpdater.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(L10n.Menu.title)
                    .font(.headline)
                Spacer()
                Button(action: {
                    DiskMonitor.shared.scanConnectedDrives()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(L10n.Menu.rescanTooltip)
            }
            .padding(.bottom, 4)

            Divider()

            // Drive List
            if store.drives.isEmpty {
                VStack(spacing: 6) {
                    Text(L10n.Menu.noDrives)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button(L10n.Menu.rescanButton) {
                        DiskMonitor.shared.scanConnectedDrives()
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(store.drives) { drive in
                    DriveRowView(drive: drive)
                    Divider()
                }
            }

            // Permission / Service Status Warnings
            if !store.isFDAAuthorized {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(L10n.Menu.warningFDA)
                        .font(.footnote)
                    Spacer()
                    Button(L10n.Menu.warningFDAButton) {
                        Permissions.openFullDiskAccessSettings()
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 2)
            }

            if !store.isHelperInstalled {
                HStack {
                    Image(systemName: "shield.slash")
                        .foregroundColor(.orange)
                    Text(L10n.Menu.warningHelper)
                        .font(.footnote)
                    Spacer()
                    Button(L10n.Menu.warningHelperButton) {
                        try? HelperInstaller.installPrivilegedHelperViaScript()
                        store.refreshPermissions()
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 2)
            }

            Divider()

            // Footer actions
            HStack {
                Button(L10n.Menu.about) {
                    AboutWindowController.shared.show()
                }
                .font(.footnote)

                Button(L10n.Menu.setup) {
                    AppDelegate.shared?.showOnboardingWindow()
                }
                .font(.footnote)

                Spacer()

                if updater.isConfigured {
                    Button(L10n.Menu.updates) {
                        updater.checkForUpdates()
                    }
                    .font(.footnote)
                }

                Button(L10n.Menu.quit) {
                    NSApp.terminate(nil)
                }
                .font(.footnote)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear {
            store.refreshPermissions()
        }
    }
}

struct DriveRowView: View {
    let drive: BitLockerDrive

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: drive.isMounted ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.person.crop")
                    .font(.title2)
                    .foregroundColor(drive.isMounted ? .green : .blue)
                VStack(alignment: .leading) {
                    Text(drive.volumeName.isEmpty ? drive.bsdName : drive.volumeName)
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(drive.bsdName) • \(drive.statusMessage)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                if drive.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if drive.isMounted {
                    if let path = drive.mountPath {
                        Button(action: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                        }) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.DriveAction.openInFinderTooltip)
                    }
                    Button(L10n.DriveAction.eject) {
                        DiskMonitor.shared.unmountDrive(bsdName: drive.bsdName)
                    }
                    .font(.caption)
                } else {
                    Button(L10n.DriveAction.unlock) {
                        DiskMonitor.shared.unlockFlow(
                            bsdName: drive.bsdName,
                            volumeName: drive.volumeName,
                            guid: drive.volumeGUID
                        )
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
