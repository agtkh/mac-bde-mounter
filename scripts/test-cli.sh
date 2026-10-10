#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI_PROBE="${ROOT}/build.nosync/cli-probe"
DISLOCKER="${ROOT}/vendor/dist/bin/dislocker"
export DYLD_LIBRARY_PATH="${ROOT}/vendor/dist/lib:${ROOT}/vendor/dist/bin:${DYLD_LIBRARY_PATH:-}"
export FUSE_NFSSRV_PATH="${ROOT}/vendor/dist/bin/fuse-t/go-nfsv4"

usage() {
  cat <<EOF
Usage: $0 <command> [arguments...]

Commands:
  unit-test               Run the full automated unit test suite (make test)
  probe <bsd1> [bsd2...]  Inspect raw sectors and test BitLocker header detection (needs sudo)
  unlock <bsd> [mountdir] Test CLI decryption using bundled dislocker (needs sudo)
  clean [mountdir]        Clean temporary test mount points

Examples:
  sudo $0 probe disk6s1 disk6s2
  sudo $0 unlock disk6s2 /tmp/blm-test
EOF
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  unit-test)
    echo "=== Running Automated Unit Test Suite ==="
    make -C "$ROOT" test
    ;;

  probe)
    if [[ $# -lt 1 ]]; then
      echo "Error: Specify at least one BSD device (e.g., disk6s1 disk6s2)" >&2
      exit 1
    fi
    if [[ ! -x "$CLI_PROBE" ]]; then
      echo "Building cli-probe..."
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
        "${ROOT}/Shared/Constants.swift" \
        "${ROOT}/Shared/Validation.swift" \
        "${ROOT}/Shared/BitLockerHeader.swift" \
        "${ROOT}/Helper/DeviceProbe.swift" \
        "${ROOT}/tools/cli-probe.swift" \
        -o "$CLI_PROBE"
    fi
    "$CLI_PROBE" "$@"
    ;;

  unlock)
    bsd="${1:-}"
    mnt="${2:-/tmp/blm-test-mnt}"
    if [[ -z "$bsd" ]]; then
      echo "Error: Specify BSD device (e.g. disk6s2)" >&2
      exit 1
    fi
    if [[ ! -x "$DISLOCKER" ]]; then
      echo "Error: Bundled dislocker not found at $DISLOCKER" >&2
      exit 1
    fi

    # Ensure fuse-t loopback alias in /etc/hosts if running as root
    if ! grep -q "[[:space:]]fuse-t" /etc/hosts 2>/dev/null; then
      echo "127.0.0.1 fuse-t" >> /etc/hosts 2>/dev/null || true
    fi

    dev="/dev/r${bsd}"
    echo "=========================================="
    echo "Testing CLI Unlock on $dev"
    echo "FUSE mount point: $mnt"
    echo "=========================================="

    mkdir -p "$mnt"
    echo -n "Enter BitLocker Password: "
    read -r -s PASSWORD
    echo ""

    echo "Running dislocker..."
    "$DISLOCKER" -v -V "$dev" -u"$PASSWORD" -- -s -o nobrowse "$mnt" || true

    echo "Waiting for dislocker-file..."
    for _ in {1..10}; do
      if [[ -f "${mnt}/dislocker-file" ]]; then
        break
      fi
      sleep 0.5
    done

    if [[ -f "${mnt}/dislocker-file" ]]; then
      echo "SUCCESS: dislocker-file created!"
      ls -lh "${mnt}/dislocker-file"
      echo ""
      echo "Attaching decrypted virtual disk via hdiutil..."
      ATTACH_OUT=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount "${mnt}/dislocker-file" 2>&1)
      echo "$ATTACH_OUT"
      VIRT_DEV=$(echo "$ATTACH_OUT" | awk '/\/dev\/disk/ {print $1}' | head -1)
      
      if [[ -n "$VIRT_DEV" ]]; then
        echo "Attached virtual device: $VIRT_DEV"
        echo "Mounting filesystem via diskutil..."
        diskutil mount "${VIRT_DEV}" 2>/dev/null || diskutil mount "${VIRT_DEV}s1" 2>/dev/null || true
        echo ""
        echo "Check Finder / /Volumes for your unlocked BitLocker drive!"
        echo ""
        echo "Press ENTER to unmount and clean up test session..."
        read -r
        
        echo "Cleaning up..."
        diskutil unmount "${VIRT_DEV}" 2>/dev/null || diskutil unmount "${VIRT_DEV}s1" 2>/dev/null || true
        hdiutil detach "$VIRT_DEV" 2>/dev/null || true
      fi
      umount "$mnt" 2>/dev/null || true
      rmdir "$mnt" 2>/dev/null || true
      echo "Test session finished cleanly."
    else
      echo "FAILURE: dislocker-file was not created."
      echo "Check password or dislocker output above."
      umount "$mnt" 2>/dev/null || true
      rmdir "$mnt" 2>/dev/null || true
      exit 1
    fi
    ;;

  clean)
    mnt="${1:-/tmp/blm-test-mnt}"
    umount "$mnt" 2>/dev/null || true
    rmdir "$mnt" 2>/dev/null || true
    echo "Cleaned $mnt"
    ;;

  *)
    usage
    ;;
esac
