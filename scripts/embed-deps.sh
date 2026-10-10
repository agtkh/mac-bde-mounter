#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME:-MacBDEMounter.app}}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Target app bundle not found: $APP_DIR" >&2
  exit 1
fi

CONTENTS="${APP_DIR}/Contents"
MAC_OS="${CONTENTS}/MacOS"
BIN_DEST="${MAC_OS}/bin"
LAUNCH_DAEMONS="${CONTENTS}/Library/LaunchDaemons"

RESOURCES_DEST="${CONTENTS}/Resources"
mkdir -p "$BIN_DEST" "$LAUNCH_DAEMONS" "$RESOURCES_DEST"

# Copy prebuilt standalone binaries
if [[ -d "${ROOT}/vendor/dist/bin" ]]; then
  echo "Embedding third-party binaries into ${BIN_DEST}..."
  rm -rf "${BIN_DEST:?}"/*
  cp -R "${ROOT}/vendor/dist/bin/"* "$BIN_DEST/"
  chmod -R 755 "$BIN_DEST"
else
  echo "WARNING: ${ROOT}/vendor/dist/bin not found. Run 'make deps' first." >&2
fi

# Copy prebuilt resource files
if [[ -d "${ROOT}/vendor/dist/resources" ]]; then
  echo "Embedding third-party resources into ${RESOURCES_DEST}..."
  cp -R "${ROOT}/vendor/dist/resources/"* "$RESOURCES_DEST/"
fi

# Copy LaunchDaemons plist for SMAppService
for p in "${ROOT}"/Config/*helper.plist; do
  if [[ -f "$p" ]]; then
    echo "Embedding LaunchDaemon plist $(basename "$p") into ${LAUNCH_DAEMONS}..."
    cp "$p" "${LAUNCH_DAEMONS}/"
  fi
done

# Copy license & OSS notice files into Resources
echo "Embedding license notices and uninstaller into ${RESOURCES_DEST}..."
cp "${ROOT}/LICENSE" "${RESOURCES_DEST}/"
cp "${ROOT}/THIRD_PARTY_NOTICES.md" "${RESOURCES_DEST}/"
cp "${ROOT}/TRADEMARKS.md" "${RESOURCES_DEST}/"
cp "${ROOT}/scripts/uninstall.sh" "${RESOURCES_DEST}/uninstall.sh"
chmod 755 "${RESOURCES_DEST}/uninstall.sh"

# Strip extended attributes (FinderInfo, resource forks, provenance) to avoid codesign errors
find "$APP_DIR" -exec xattr -c {} + 2>/dev/null || true
find "$APP_DIR" -type l -exec xattr -s -c {} + 2>/dev/null || true

echo "Embedding complete."
