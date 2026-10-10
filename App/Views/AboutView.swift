// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI

public final class AboutWindowController {
    public static let shared = AboutWindowController()
    private var window: NSWindow?

    private init() {}

    public func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)
        let win = NSWindow(contentViewController: hostingController)
        win.title = L10n.About.windowTitle
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.center()
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 660, height: 520))
        win.minSize = NSSize(width: 600, height: 460)

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

public struct OSSComponent: Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String
    public let licenseName: String
    public let repositoryURL: String
    public let purpose: String
    public let licenseNotice: String
}

public struct AboutView: View {
    private var components: [OSSComponent] {
        [
            OSSComponent(
                id: "dislocker",
                name: "dislocker",
                version: "0.7.3",
                author: "Romain Coltel and contributors",
                licenseName: "GNU General Public License v2.0 (GPL-2.0)",
                repositoryURL: "https://github.com/Aorimn/dislocker",
                purpose: L10n.OSSPurpose.dislocker,
                licenseNotice: """
                Copyright (C) 2011-2023 Romain Coltel

                This program is free software; you can redistribute it and/or modify
                it under the terms of the GNU General Public License as published by
                the Free Software Foundation, either version 2 of the License, or
                (at your option) any later version.

                This program is distributed in the hope that it will be useful,
                but WITHOUT ANY WARRANTY; without even the implied warranty of
                MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
                GNU General Public License for more details.

                You should have received a copy of the GNU General Public License
                along with this program; if not, write to the Free Software
                Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
                """
            ),
            OSSComponent(
                id: "fuse-t",
                name: "FUSE-T",
                version: "1.2.7",
                author: "Anatol Pomozov / macos-fuse-t",
                licenseName: "Free for non-commercial use / LGPL v2.1 (libfuse)",
                repositoryURL: "https://github.com/macos-fuse-t/fuse-t",
                purpose: L10n.OSSPurpose.fuset,
                licenseNotice: """
                Copyright (C) Anatol Pomozov / macos-fuse-t

                The binary distribution of FUSE-T (go-nfsv4) is licensed under the following terms:

                - Free for non-commercial use under the following conditions:
                  1. Redistributions of source code must retain the above copyright notice,
                     this list of conditions and the following disclaimer.
                  2. Redistributions in binary form must reproduce the above copyright notice,
                     this list of conditions and the following disclaimer in the documentation
                     and/or other materials provided with the distribution.
                  3. Neither the name of the copyright holder nor the names of its contributors
                     may be used to endorse or promote products derived from this software
                     without specific prior written permission.

                DISCLAIMER:
                THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
                AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
                IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
                DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
                FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
                DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
                SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
                CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
                OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
                OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

                - For commercial use or/and bundling with commercial software:
                  The software vendor has to obtain a commercial license from the FUSE-T authors.

                - libfuse library:
                  GNU Lesser General Public License (LGPL v2.1). Forked from https://github.com/osxfuse/fuse
                """
            ),
            OSSComponent(
                id: "mbedtls",
                name: "mbedTLS",
                version: "3.6.7",
                author: "TrustedFirmware.org / ARM Limited",
                licenseName: "GPL-2.0-or-later (dual-licensed with Apache 2.0)",
                repositoryURL: "https://github.com/Mbed-TLS/mbedtls",
                purpose: L10n.OSSPurpose.mbedtls,
                licenseNotice: """
                Copyright (C) 2006-2024 ARM Limited. All rights reserved.

                Dual-licensed under the Apache License, Version 2.0 OR the GNU General Public
                License, version 2.0 or later.

                Mac BDE Mounter statically links mbedTLS under the GPL-2.0-or-later option:

                This program is free software; you can redistribute it and/or modify
                it under the terms of the GNU General Public License as published by
                the Free Software Foundation; either version 2 of the License, or
                (at your option) any later version.

                This program is distributed in the hope that it will be useful,
                but WITHOUT ANY WARRANTY; without even the implied warranty of
                MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
                GNU General Public License for more details.
                """
            ),
            OSSComponent(
                id: "sparkle",
                name: "Sparkle",
                version: "2.6.4",
                author: "Andy Matuschak and the Sparkle Project contributors",
                licenseName: "MIT License",
                repositoryURL: "https://github.com/sparkle-project/Sparkle",
                purpose: L10n.OSSPurpose.sparkle,
                licenseNotice: """
                Copyright (c) 2006-2013 Andy Matuschak.
                Copyright (c) 2009-2013 Elgato Systems GmbH.
                Copyright (c) 2011-2014 Kornel Lesiński.
                Copyright (c) 2015-2017 Mayur Pawashe.
                Copyright (c) 2014 C.W. Betts.
                Copyright (c) 2014 Petroules Corporation.
                Copyright (c) 2014 Big Nerd Ranch.
                All rights reserved.

                Permission is hereby granted, free of charge, to any person obtaining a copy of
                this software and associated documentation files (the "Software"), to deal in
                the Software without restriction, including without limitation the rights to
                use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
                the Software, and to permit persons to whom the Software is furnished to do so,
                subject to the following conditions:

                The above copyright notice and this permission notice shall be included in all
                copies or substantial portions of the Software.

                THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
                IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
                FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
                COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
                IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
                CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

                [Includes bsdiff (Colin Percival), sais-lite (Yuta Mori), Ed25519 (Orson Peters)]
                """
            )
        ]
    }

    @State private var selectedComponentId: String = "dislocker"
    @State private var showTrademarks: Bool = false

    public init() {}

    private var selectedComponent: OSSComponent {
        components.first(where: { $0.id == selectedComponentId }) ?? components[0]
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return L10n.versionString(version: version, build: build)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // App Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(L10n.appName)
                                .font(.title3)
                                .fontWeight(.bold)
                            Text(appVersion)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                Text(L10n.authorLabel)
                                    .foregroundColor(.secondary)
                                Text(L10n.authorName)
                                    .fontWeight(.semibold)
                            }

                            Text("•")
                                .foregroundColor(.secondary.opacity(0.4))

                            Text(L10n.About.mainLicense)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                    Spacer()
                }

                // Trademarks & Disclaimers disclosure
                DisclosureGroup(isExpanded: $showTrademarks) {
                    Text(L10n.About.trademarkBody)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                } label: {
                    Text(L10n.About.trademarkTitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 60)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // OSS List & Tied License Details (Master-Detail)
            HStack(spacing: 0) {
                // Left OSS List
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.About.ossHeader)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)

                    List(components, selection: $selectedComponentId) { comp in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(comp.name)
                                .font(.system(size: 13, weight: .bold))
                            Text(comp.licenseName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 3)
                        .tag(comp.id)
                    }
                    .listStyle(.sidebar)
                }
                .frame(width: 200)

                Divider()

                // Right Detail View (License tied to selected OSS)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(selectedComponent.name)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Text("v\(selectedComponent.version)")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            Text("\(L10n.About.authorLabel) \(selectedComponent.author)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()

                        if let url = URL(string: selectedComponent.repositoryURL) {
                            Link(L10n.About.repoLink, destination: url)
                                .font(.caption)
                        }
                    }

                    // License Name Badge
                    HStack {
                        Text(L10n.About.licenseLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(selectedComponent.licenseName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }

                    Text(selectedComponent.purpose)
                        .font(.caption)
                        .foregroundColor(.primary)

                    Divider()

                    Text(L10n.About.noticeLabel)
                        .font(.caption)
                        .fontWeight(.semibold)

                    // Scrollable License Notice Box
                    ScrollView {
                        Text(selectedComponent.licenseNotice)
                            .font(.system(size: 11, design: .monospaced))
                            .lineSpacing(2)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Footer
            HStack {
                Button(L10n.About.viewLicense) {
                    openBundledFile(named: "LICENSE")
                }
                .font(.footnote)

                Button(L10n.About.viewNotices) {
                    openBundledFile(named: "THIRD_PARTY_NOTICES.md")
                }
                .font(.footnote)

                Button("TRADEMARKS.md") {
                    openBundledFile(named: "TRADEMARKS.md")
                }
                .font(.footnote)

                Spacer()

                Button(L10n.About.uninstall) {
                    AppUninstaller.confirmAndUninstall()
                }
                .font(.footnote)

                Button(L10n.About.close) {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 640, minHeight: 490)
    }

    private func openBundledFile(named name: String) {
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            NSWorkspace.shared.open(url)
        } else if let url = Bundle.main.resourceURL?.appendingPathComponent(name), FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            let alert = NSAlert()
            alert.messageText = L10n.About.notFound(name)
            alert.alertStyle = .informational
            alert.runModal()
        }
    }
}
