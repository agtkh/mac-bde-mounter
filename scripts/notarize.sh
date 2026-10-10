#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

DMG="${1:-build.nosync/MacBDEMounter.dmg}"
PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"

if [[ ! -f "$DMG" ]]; then
  echo "DMG not found: $DMG" >&2
  exit 1
fi

if [[ -z "$PROFILE" ]]; then
  echo "NOTARY_KEYCHAIN_PROFILE is not set. Skipping notarization."
  exit 0
fi

echo "Submitting $DMG for notarization using profile '$PROFILE'..."
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "Stapling notarization ticket to $DMG..."
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "Notarization complete."
