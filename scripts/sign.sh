#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-${ROOT}/build.nosync/Release/MacBDEMounter.app}"
IDENTITY="${IDENTITY:--}"
ENT_APP="${ROOT}/Config/App.entitlements"
ENT_HELPER="${ROOT}/Config/Helper.entitlements"

if [[ ! -d "$APP" ]]; then
  echo "Application bundle not found: $APP" >&2
  exit 1
fi

clean_xattrs() {
  local target="${1:-$APP}"
  if command -v SetFile &>/dev/null; then
    SetFile -a b "$target" 2>/dev/null || true
    find "$target" -exec SetFile -a b {} + 2>/dev/null || true
  fi
  xattr -d com.apple.FinderInfo "$target" 2>/dev/null || true
  xattr -d -s com.apple.FinderInfo "$target" 2>/dev/null || true
  find "$target" -exec xattr -d com.apple.FinderInfo {} + 2>/dev/null || true
  find "$target" -exec xattr -d -s com.apple.FinderInfo {} + 2>/dev/null || true
  find "$target" -exec xattr -d com.apple.ResourceFork {} + 2>/dev/null || true
  find "$target" -exec xattr -d -s com.apple.ResourceFork {} + 2>/dev/null || true
}

clean_xattrs "$APP"

echo "Signing application bundle at $APP with identity '$IDENTITY'..."

SIGN_OPTS=(--force)
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_OPTS+=(--options runtime --timestamp)
fi

sign_item() {
  local item="$1"
  local ent="${2:-}"
  if [[ -e "$item" ]]; then
    clean_xattrs "$item"
    if [[ -n "$ent" && -f "$ent" ]]; then
      codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" --entitlements "$ent" "$item"
    else
      codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" "$item"
    fi
  fi
}


# 1. Sign internal helper binaries & dylibs
sign_item "${APP}/Contents/MacOS/bin/fuse-t/go-nfsv4"
sign_item "${APP}/Contents/MacOS/bin/libdislocker.dylib"
sign_item "${APP}/Contents/MacOS/bin/dislocker"

# 2. Sign embedded frameworks and their nested bundles inside-out
if [[ -d "${APP}/Contents/Frameworks" ]]; then
  for fw in "${APP}/Contents/Frameworks/"*.framework; do
    if [[ -d "$fw" ]]; then
      for vdir in "$fw"/Versions/*; do
        [[ -L "$vdir" ]] && continue
        for xpc in "$vdir"/XPCServices/*.xpc; do
          [[ -d "$xpc" && ! -L "$xpc" ]] && sign_item "$xpc"
        done
        for nested_app in "$vdir"/Updater.app; do
          [[ -d "$nested_app" && ! -L "$nested_app" ]] && sign_item "$nested_app"
        done
        for bin in "$vdir"/Autoupdate; do
          [[ -f "$bin" && ! -L "$bin" ]] && sign_item "$bin"
        done
      done
      sign_item "$fw"
    fi
  done
fi

# 3. Sign Privileged Helper daemon
clean_xattrs "${APP}/Contents/MacOS/MacBDEMounterHelper"
codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" -r '= designated => identifier "top.agata.MacBDEMounter.helper"' --entitlements "$ENT_HELPER" "${APP}/Contents/MacOS/MacBDEMounterHelper"

# 4. Sign top-level application bundle
clean_xattrs "$APP"
codesign "${SIGN_OPTS[@]}" --sign "$IDENTITY" -r '= designated => identifier "top.agata.MacBDEMounter"' --entitlements "$ENT_APP" "$APP"

echo "Verifying code signature..."
clean_xattrs
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Code signature valid."
