# SPDX-License-Identifier: GPL-2.0-or-later

DEVELOPER_DIR ?= $(shell if [ -d /Applications/Xcode.app/Contents/Developer ]; then echo /Applications/Xcode.app/Contents/Developer; else xcode-select -p; fi)
export DEVELOPER_DIR

CONFIG ?= Debug
SCHEME ?= MacBDEMounter
PROJECT = MacBDEMounter.xcodeproj
IDENTITY ?= -
TEAM_ID ?=
BUILD_DIR = build.nosync
APP_BUNDLE = $(BUILD_DIR)/$(CONFIG)/MacBDEMounter.app

.PHONY: all deps icons project build test sign self-sign dmg notarize dev-install-helper dev-uninstall-helper uninstall run clean

all: build

deps:
	./scripts/build-deps.sh

icons:
	python3 ./scripts/generate-icons.py

project:
	xcodegen generate

build: project
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="$(IDENTITY)" \
		CODE_SIGN_STYLE=Manual \
		build
	@mkdir -p $(BUILD_DIR)/$(CONFIG)
	@BUILT_APP=$$(DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR =/ {print $$3}')/MacBDEMounter.app; \
	rm -rf "$(APP_BUNDLE)"; \
	ditto --noextattr --noqtn "$$BUILT_APP" "$(APP_BUNDLE)"; \
	find "$(APP_BUNDLE)" -exec xattr -c {} + 2>/dev/null || true; \
	find "$(APP_BUNDLE)" -type l -exec xattr -s -c {} + 2>/dev/null || true
	@echo "Application built at: $(APP_BUNDLE)"

test: project
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild \
		-project $(PROJECT) \
		-scheme MacBDEMounterTests \
		-configuration Debug \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGN_STYLE=Manual \
		test

cli-probe:
	@mkdir -p $(BUILD_DIR)
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun swiftc \
		Shared/Constants.swift \
		Shared/Validation.swift \
		Shared/BitLockerHeader.swift \
		Helper/DeviceProbe.swift \
		tools/cli-probe.swift \
		-o $(BUILD_DIR)/cli-probe

sign:
	./scripts/sign.sh "$(APP_BUNDLE)"

self-sign:
	./scripts/self-sign.sh "/Applications/MacBDEMounter.app"

dmg: sign
	./scripts/make-dmg.sh "$(APP_BUNDLE)" "$(BUILD_DIR)/MacBDEMounter.dmg"

notarize:
	./scripts/notarize.sh "$(BUILD_DIR)/MacBDEMounter.dmg"

dev-install-helper:
	@echo "Installing helper daemon into /Library/PrivilegedHelperTools and /Library/LaunchDaemons..."
	sudo mkdir -p "/Library/PrivilegedHelperTools" "/Library/LaunchDaemons" "/Library/Application Support/MacBDEMounter"
	sudo cp -f "$(APP_BUNDLE)/Contents/MacOS/MacBDEMounterHelper" "/Library/PrivilegedHelperTools/top.agata.MacBDEMounter.helper"
	sudo chown root:wheel "/Library/PrivilegedHelperTools/top.agata.MacBDEMounter.helper"
	sudo chmod 755 "/Library/PrivilegedHelperTools/top.agata.MacBDEMounter.helper"
	@TMP_PLIST=$$(mktemp /tmp/blm-helper-plist.XXXXXX); \
	printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>Label</key>\n\t<string>top.agata.MacBDEMounter.helper</string>\n\t<key>ProgramArguments</key>\n\t<array>\n\t\t<string>/Library/PrivilegedHelperTools/top.agata.MacBDEMounter.helper</string>\n\t</array>\n\t<key>MachServices</key>\n\t<dict>\n\t\t<key>top.agata.MacBDEMounter.helper</key>\n\t\t<true/>\n\t</dict>\n</dict>\n</plist>\n' > "$$TMP_PLIST"; \
	sudo cp -f "$$TMP_PLIST" "/Library/LaunchDaemons/top.agata.MacBDEMounter.helper.plist"; \
	rm -f "$$TMP_PLIST"
	sudo chown root:wheel "/Library/LaunchDaemons/top.agata.MacBDEMounter.helper.plist"
	sudo chmod 644 "/Library/LaunchDaemons/top.agata.MacBDEMounter.helper.plist"
	sudo launchctl bootout system/top.agata.MacBDEMounter.helper 2>/dev/null || true
	sudo launchctl bootout system "/Library/LaunchDaemons/top.agata.MacBDEMounter.helper.plist" 2>/dev/null || true
	sudo launchctl enable system/top.agata.MacBDEMounter.helper
	sudo launchctl bootstrap system "/Library/LaunchDaemons/top.agata.MacBDEMounter.helper.plist"
	sudo launchctl kickstart -kp system/top.agata.MacBDEMounter.helper
	@echo "Helper daemon installed and restarted."

dev-uninstall-helper:
	@echo "Uninstalling development helper daemon..."
	sudo launchctl bootout system "/Library/LaunchDaemons/top.agata.MacBDEMounter.helper.plist" 2>/dev/null || true
	sudo rm -f "/Library/LaunchDaemons/top.agata.MacBDEMounter.helper.plist"
	@echo "Helper daemon uninstalled."

l10n-check:
	./scripts/check-l10n.sh

uninstall:
	@echo "Running complete system uninstaller..."
	sudo ./scripts/uninstall.sh

run:
	open "$(APP_BUNDLE)"

clean:
	rm -rf $(BUILD_DIR) build $(PROJECT) vendor/dist
