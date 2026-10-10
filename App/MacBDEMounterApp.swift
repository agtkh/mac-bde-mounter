// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    public static var shared: AppDelegate?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
           NSClassFromString("XCTestCase") != nil {
            return
        }

        // Ensure app does not activate as a standard windowed app (menu bar utility)
        NSApp.setActivationPolicy(.accessory)

        // Configure user notifications
        NotificationManager.shared.configure()

        // Start disk monitor
        DiskMonitor.shared.start()

        // Check if onboarding is needed
        DriveStore.shared.refreshPermissions()
        if !DriveStore.shared.isFDAAuthorized || !DriveStore.shared.isHelperInstalled || !DriveStore.shared.isHelperFDAAuthorized {
            showOnboardingWindow()
        }
    }

    public func showOnboardingWindow() {
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = L10n.Onboarding.windowTitle
        window.contentView = NSHostingView(rootView: OnboardingView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }
}

@main
struct MacBDEMounterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}
