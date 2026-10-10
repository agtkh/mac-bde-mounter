// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import AppKit

public struct OnboardingView: View {
    @ObservedObject var store = DriveStore.shared
    @State private var isInstallingHelper: Bool = false
    @State private var helperErrorMessage: String? = nil

    @State private var hasLegacyApp: Bool = HelperInstaller.legacyAppExists

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(L10n.Onboarding.title)
                .font(.title2)
                .bold()

            Text(L10n.Onboarding.description)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            if hasLegacyApp {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Onboarding.legacyTitle)
                            .font(.caption)
                            .bold()
                        Text(L10n.Onboarding.legacyDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(L10n.Onboarding.legacyTrash) {
                        try? HelperInstaller.trashLegacyApp()
                        hasLegacyApp = HelperInstaller.legacyAppExists
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
            }

            VStack(alignment: .leading, spacing: 18) {
                // 1. Full Disk Access
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: store.isFDAAuthorized ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(store.isFDAAuthorized ? .green : .secondary)
                            .imageScale(.large)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.Onboarding.fdaTitle)
                                .font(.headline)
                            Text(L10n.Onboarding.fdaDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !store.isFDAAuthorized {
                            Button(L10n.Onboarding.fdaButton) {
                                Permissions.openFullDiskAccessSettings()
                            }
                        }
                    }

                    if !store.isFDAAuthorized {
                        HStack(spacing: 8) {
                            Text(L10n.Onboarding.fdaRestartNotice)
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Spacer()
                            Button(L10n.Onboarding.fdaRelaunchButton) {
                                relaunchApp()
                            }
                            .font(.caption)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
                    }
                }

                Divider()

                // 2. Privileged Helper Daemon
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: store.isHelperInstalled ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(store.isHelperInstalled ? .green : .secondary)
                            .imageScale(.large)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.Onboarding.helperTitle)
                                .font(.headline)
                            Text(L10n.Onboarding.helperDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !store.isHelperInstalled {
                            if isInstallingHelper {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button(L10n.Onboarding.helperInstall) {
                                    installHelper()
                                }
                            }
                        } else {
                            if isInstallingHelper {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button(L10n.Onboarding.helperReinstall) {
                                    installHelper()
                                }
                                .font(.caption)
                            }
                        }
                    }

                    if let err = helperErrorMessage {
                        Text(L10n.Common.error(err))
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    if store.isHelperInstalled && !store.isHelperFDAAuthorized {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(L10n.Onboarding.helperFDATitle(BLMConstants.machServiceName))
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.orange)
                            }
                            Text(L10n.Onboarding.helperFDADescription)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            HStack {
                                Spacer()
                                Button(L10n.Onboarding.helperFDARevealButton) {
                                    Permissions.openFullDiskAccessSettings()
                                    Permissions.revealHelperInFinder()
                                }
                                .font(.caption)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))

            HStack {
                Button(L10n.Onboarding.recheck) {
                    store.refreshPermissions()
                    hasLegacyApp = HelperInstaller.legacyAppExists
                }
                .font(.footnote)

                Spacer()

                Button(L10n.Onboarding.uninstall) {
                    AppUninstaller.confirmAndUninstall()
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundColor(.secondary)

                Button(L10n.Onboarding.done) {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!store.isFDAAuthorized || !store.isHelperInstalled || !store.isHelperFDAAuthorized)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            store.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshPermissions()
        }
    }

    private func installHelper() {
        isInstallingHelper = true
        helperErrorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try HelperInstaller.register()
                Thread.sleep(forTimeInterval: 0.3)
                DispatchQueue.main.async {
                    self.isInstallingHelper = false
                    self.store.refreshPermissions()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstallingHelper = false
                    self.helperErrorMessage = error.localizedDescription
                    self.store.refreshPermissions()
                }
            }
        }
    }

    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
