#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Mac BDE Mounter - Initial Setup & Gatekeeper Unlock Tool
#
# This tool removes macOS download quarantine (Gatekeeper block)
# and ensures the application bundle and all embedded components
# (Helper daemon, dislocker, FUSE-T, Sparkle framework) are validated
# and ready for execution without requiring Xcode, Homebrew, or source compilation.

set -euo pipefail

# Text formatting
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${BOLD}${CYAN}====================================================${RESET}"
echo -e "${BOLD}${CYAN}      Mac BDE Mounter - Initial Setup Tool          ${RESET}"
echo -e "${BOLD}${CYAN}====================================================${RESET}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_APP="${1:-/Applications/MacBDEMounter.app}"
IDENTITY="${2:-${IDENTITY:--}}"

# Check if application exists at target path
if [[ ! -d "$TARGET_APP" ]]; then
  # Check if user ran this script directly from the DMG staging directory
  DMG_APP="${SCRIPT_DIR}/MacBDEMounter.app"
  if [[ -d "$DMG_APP" ]]; then
    echo -e "${YELLOW}[!] MacBDEMounter.app is not found in /Applications.${RESET}"
    echo -e "    Found application in current directory: ${DMG_APP}"
    read -r -p "    Would you like to copy it to /Applications now? (y/N): " answer || true
    if [[ "${answer:-}" =~ ^[Yy]$ ]]; then
      echo "--> Copying MacBDEMounter.app to /Applications..."
      ditto --noextattr --noqtn "$DMG_APP" "/Applications/MacBDEMounter.app"
      TARGET_APP="/Applications/MacBDEMounter.app"
      echo -e "${GREEN}[✓] Successfully copied to /Applications.${RESET}"
    else
      echo -e "${RED}[✗] Installation aborted. Please copy MacBDEMounter.app to /Applications first.${RESET}"
      exit 1
    fi
  else
    echo -e "${RED}[✗] Application not found at: ${TARGET_APP}${RESET}"
    echo "    Please drag MacBDEMounter.app into /Applications before running this script."
    exit 1
  fi
fi

echo -e "Target Application : ${BOLD}${TARGET_APP}${RESET}"
echo -e "Signing Identity   : ${BOLD}${IDENTITY}${RESET} (ad-hoc / local signature)"
echo ""

# 1. Clean quarantine and extended attributes
echo -e "${CYAN}--> Step 1/3: Clearing macOS download quarantine (Gatekeeper)...${RESET}"
if command -v xattr &>/dev/null; then
  xattr -cr "$TARGET_APP" 2>/dev/null || true
  xattr -s -c "$TARGET_APP" 2>/dev/null || true
  find "$TARGET_APP" -exec xattr -c {} + 2>/dev/null || true
  find "$TARGET_APP" -type l -exec xattr -s -c {} + 2>/dev/null || true
fi
echo -e "${GREEN}[✓] Quarantine attributes removed.${RESET}"
echo ""

# 2. Re-sign nested components inside-out
echo -e "${CYAN}--> Step 2/3: Initializing local application signatures & components...${RESET}"

SIGN_OPTS=(--force)
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_OPTS+=(--options runtime --timestamp)
fi

sign_file() {
  local item="$1"
  local ent="${2:-}"
  if [[ -e "$item" ]]; then
    if [[ -n "$ent" && -f "$ent" ]]; then
      codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" --entitlements "$ent" "$item" 2>/dev/null || \
      codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" "$item"
    else
      codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" "$item"
    fi
  fi
}

# Sign internal helper binaries & dylibs
sign_file "${TARGET_APP}/Contents/MacOS/bin/fuse-t/go-nfsv4"
sign_file "${TARGET_APP}/Contents/MacOS/bin/libdislocker.dylib"
sign_file "${TARGET_APP}/Contents/MacOS/bin/dislocker"

# Sign embedded frameworks and their nested bundles inside-out
if [[ -d "${TARGET_APP}/Contents/Frameworks" ]]; then
  for fw in "${TARGET_APP}/Contents/Frameworks/"*.framework; do
    if [[ -d "$fw" ]]; then
      for vdir in "$fw"/Versions/*; do
        [[ -L "$vdir" ]] && continue
        for xpc in "$vdir"/XPCServices/*.xpc; do
          [[ -d "$xpc" && ! -L "$xpc" ]] && sign_file "$xpc"
        done
        for nested_app in "$vdir"/Updater.app; do
          [[ -d "$nested_app" && ! -L "$nested_app" ]] && sign_file "$nested_app"
        done
        for bin in "$vdir"/Autoupdate; do
          [[ -f "$bin" && ! -L "$bin" ]] && sign_file "$bin"
        done
      done
      sign_file "$fw"
    fi
  done
fi

# Sign Privileged Helper daemon
if [[ -f "${TARGET_APP}/Contents/MacOS/MacBDEMounterHelper" ]]; then
  codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" -r '= designated => identifier "top.agata.MacBDEMounter.helper"' "${TARGET_APP}/Contents/MacOS/MacBDEMounterHelper"
fi

# Sign top-level application bundle
codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" -r '= designated => identifier "top.agata.MacBDEMounter"' "$TARGET_APP"

echo -e "${GREEN}[✓] Application bundle and internal components signed.${RESET}"
echo ""

# 3. Verify signature
echo -e "${CYAN}--> Step 3/3: Verifying code signature...${RESET}"
codesign --verify --deep --strict "$TARGET_APP"
echo -e "${GREEN}[✓] Code signature verification passed!${RESET}"
echo ""

echo -e "${BOLD}${GREEN}====================================================${RESET}"
echo -e "${BOLD}${GREEN}        Setup completed successfully!               ${RESET}"
echo -e "${BOLD}${GREEN}====================================================${RESET}"
echo ""
echo -e "Important Note / 重要な注意事項:"
echo -e "1. On first launch, grant ${BOLD}Full Disk Access${RESET} (フルディスクアクセス):"
echo -e "   System Settings > Privacy & Security > Full Disk Access -> enable Mac BDE Mounter."
echo -e "2. When prompted, enter your administrator password or Touch ID"
echo -e "   to install the background helper daemon."
echo ""

read -r -p "Launch Mac BDE Mounter now? / 今すぐ起動しますか？ (Y/n): " launch_ans || true
if [[ ! "${launch_ans:-}" =~ ^[Nn]$ ]]; then
  echo "Launching ${TARGET_APP}..."
  open "$TARGET_APP" 2>/dev/null || true
fi

echo ""
echo "Press [Enter] to exit. / Enterキーを押して終了します。"
read -r _ || true
