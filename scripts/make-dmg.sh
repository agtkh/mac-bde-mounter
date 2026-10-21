#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-${ROOT}/build.nosync/Release/MacBDEMounter.app}"
OUTPUT_DMG="${2:-${ROOT}/build.nosync/MacBDEMounter.dmg}"

if [[ ! -d "$APP" ]]; then
  echo "Application not found at $APP" >&2
  exit 1
fi

STAGING="$(mktemp -d -t blm-dmg.nosync)"
trap 'rm -rf "$STAGING"' EXIT

echo "Creating DMG staging directory..."
cp -R "$APP" "$STAGING/"
ln -s /Applications "${STAGING}/Applications"
cp "${ROOT}/LICENSE" "${STAGING}/LICENSE.txt"
cp "${ROOT}/THIRD_PARTY_NOTICES.md" "${STAGING}/THIRD_PARTY_NOTICES.txt"
cp "${ROOT}/TRADEMARKS.md" "${STAGING}/TRADEMARKS.txt"
cp "${ROOT}/scripts/setup.sh" "${STAGING}/Setup.command"
chmod 755 "${STAGING}/Setup.command"
cp "${ROOT}/scripts/uninstall.sh" "${STAGING}/Uninstall.command"
chmod 755 "${STAGING}/Uninstall.command"

# Clean any extended attributes or detritus from staging
if command -v xattr &>/dev/null; then
  xattr -cr "$STAGING" 2>/dev/null || true
  find "$STAGING" -exec xattr -c {} + 2>/dev/null || true
  find "$STAGING" -type l -exec xattr -s -c {} + 2>/dev/null || true
fi

# Set DMG volume icon
if [[ -f "${ROOT}/App/Resources/AppIcon.icns" ]]; then
  cp "${ROOT}/App/Resources/AppIcon.icns" "${STAGING}/.VolumeIcon.icns"
  SetFile -c icnC "${STAGING}/.VolumeIcon.icns" 2>/dev/null || true
  SetFile -a C "${STAGING}" 2>/dev/null || true
fi

echo "Building DMG..."
mkdir -p "$(dirname "$OUTPUT_DMG")"
hdiutil create -volname "Mac BDE Mounter" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$OUTPUT_DMG"

echo "DMG created at $OUTPUT_DMG"
