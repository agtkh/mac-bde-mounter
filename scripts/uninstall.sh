#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Mac BDE Mounter - Complete System Uninstaller
# This script completely removes Mac BDE Mounter (and any legacy BitLocker Mounter files),
# its privileged helper daemon, FUSE-T components, temporary mount points,
# caches, preferences, and permissions.

set -euo pipefail

# Ensure script is run with root privileges
if [[ $EUID -ne 0 ]]; then
  echo "Administrator privileges are required to completely remove Mac BDE Mounter."
  exec sudo bash "$0" "$@"
fi

echo "=================================================="
echo "    Mac BDE Mounter - Complete Uninstallation"
echo "=================================================="

# 1. Unmount any active BitLocker virtual drives & detach disk images
echo "[1/8] Unmounting volumes and detaching virtual disk images..."
/usr/bin/python3 -c "
import plistlib, subprocess
try:
    p = subprocess.run(['/usr/bin/hdiutil', 'info', '-plist'], capture_output=True)
    if p.returncode == 0 and p.stdout:
        pl = plistlib.loads(p.stdout)
        for img in pl.get('images', []):
            path = img.get('image-path', '')
            if 'dislocker' in path:
                for entity in img.get('system-entities', []):
                    dev = entity.get('dev-entry')
                    if dev:
                        subprocess.run(['/usr/sbin/diskutil', 'unmount', 'force', dev], capture_output=True)
                        subprocess.run(['/usr/bin/hdiutil', 'detach', dev, '-force'], capture_output=True)
except Exception:
    pass
" 2>/dev/null || true

# Force unmount any FUSE/NFS dislocker mount points
for mp in /private/tmp/dislocker_* /tmp/dislocker_*; do
  if [[ -d "$mp" ]]; then
    echo "  Unmounting $mp..."
    for _ in {1..5}; do
      /sbin/umount -f "$mp" 2>/dev/null || break
    done
    rm -rf "$mp" 2>/dev/null || true
  fi
done

for arg in "$@"; do
  if [[ "$arg" == "--from-app" ]]; then
    BLM_FROM_APP=1
  fi
done

# 2. Terminate all related processes
echo "[2/8] Terminating application and helper processes..."
if [[ "${BLM_FROM_APP:-0}" != "1" ]]; then
  killall "MacBDEMounter" 2>/dev/null || true
  killall "BitLockerMounter" 2>/dev/null || true
fi
/usr/bin/pkill -9 -f "dislocker" 2>/dev/null || true
/usr/bin/pkill -9 -f "go-nfsv4" 2>/dev/null || true
/usr/bin/pkill -9 -f "top.agata.MacBDEMounter.helper" 2>/dev/null || true
/usr/bin/pkill -9 -f "top.agata.BitLockerMounter.helper" 2>/dev/null || true

# 3. Stop and unregister Privileged Helper Daemons
echo "[3/8] Unregistering and removing Privileged Helper Daemons..."
/bin/launchctl bootout system/top.agata.MacBDEMounter.helper 2>/dev/null || true
/bin/launchctl bootout system/top.agata.BitLockerMounter.helper 2>/dev/null || true
/bin/launchctl bootout system /Library/LaunchDaemons/top.agata.MacBDEMounter.helper.plist 2>/dev/null || true
/bin/launchctl bootout system /Library/LaunchDaemons/top.agata.BitLockerMounter.helper.plist 2>/dev/null || true
/bin/launchctl enable system/top.agata.MacBDEMounter.helper 2>/dev/null || true
/bin/launchctl enable system/top.agata.BitLockerMounter.helper 2>/dev/null || true

rm -f "/Library/LaunchDaemons/top.agata.MacBDEMounter.helper.plist"
rm -f "/Library/LaunchDaemons/top.agata.BitLockerMounter.helper.plist"
rm -f "/Library/LaunchDaemons/top.agata.bitlockermounter.helper.plist"
rm -f "/Library/PrivilegedHelperTools/top.agata.MacBDEMounter.helper"
rm -f "/Library/PrivilegedHelperTools/top.agata.BitLockerMounter.helper"

# 4. Remove system-wide Application Support files (FUSE-T, binaries)
echo "[4/8] Removing system application support files..."
rm -rf "/Library/Application Support/MacBDEMounter"
rm -rf "/Library/Application Support/top.agata.MacBDEMounter"
rm -rf "/Library/Application Support/BitLockerMounter"
rm -rf "/Library/Application Support/top.agata.BitLockerMounter"

# 5. Clean up temporary directories and logs
echo "[5/8] Cleaning up temporary files and logs..."
rm -f /tmp/blm-* /private/tmp/blm-*
rm -rf /private/tmp/dislocker_* /tmp/dislocker_*

# 6. Remove user-level preferences, caches, application state
echo "[6/8] Removing user preferences, caches, and application state..."
TARGET_USERS=()
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  TARGET_USERS+=("$SUDO_USER")
fi
CONSOLE_USER=$(stat -f "%Su" /dev/console 2>/dev/null || true)
if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" ]]; then
  TARGET_USERS+=("$CONSOLE_USER")
fi

for u in $(printf "%s\n" "${TARGET_USERS[@]}" | sort -u); do
  UHOME=$(eval echo "~$u")
  if [[ -d "$UHOME" ]]; then
    echo "  Cleaning data for user: $u..."
    rm -rf "$UHOME/Library/Caches/top.agata.MacBDEMounter"*
    rm -rf "$UHOME/Library/Caches/top.agata.BitLockerMounter"*
    rm -rf "$UHOME/Library/Preferences/top.agata.MacBDEMounter"*
    rm -rf "$UHOME/Library/Preferences/top.agata.BitLockerMounter"*
    rm -rf "$UHOME/Library/Preferences/ByHost/top.agata.MacBDEMounter"*
    rm -rf "$UHOME/Library/Preferences/ByHost/top.agata.BitLockerMounter"*
    rm -rf "$UHOME/Library/Saved Application State/top.agata.MacBDEMounter"*
    rm -rf "$UHOME/Library/Saved Application State/top.agata.BitLockerMounter"*
    rm -rf "$UHOME/Library/HTTPStorages/top.agata.MacBDEMounter"*
    rm -rf "$UHOME/Library/HTTPStorages/top.agata.BitLockerMounter"*
    rm -rf "$UHOME/Library/Application Support/MacBDEMounter"*
    rm -rf "$UHOME/Library/Application Support/top.agata.MacBDEMounter"*
    rm -rf "$UHOME/Library/Application Support/BitLockerMounter"*
    rm -rf "$UHOME/Library/Application Support/top.agata.BitLockerMounter"*
    rm -rf "$UHOME/Library/Logs/MacBDEMounter"*
    rm -rf "$UHOME/Library/Logs/BitLockerMounter"*
    rm -rf "$UHOME/Library/Logs/fuse-t"*
    sudo -u "$u" defaults delete top.agata.MacBDEMounter 2>/dev/null || true
    sudo -u "$u" defaults delete top.agata.BitLockerMounter 2>/dev/null || true
  fi
done

# 7. Unregister from LaunchServices and remove Application bundle
echo "[7/8] Removing application bundles..."
APP_PATHS=("/Applications/MacBDEMounter.app" "/Applications/BitLockerMounter.app")
if [[ $# -gt 0 && -d "$1" ]]; then
  APP_PATHS+=("$1")
fi
if [[ -n "${APP_BUNDLE_PATH:-}" && -d "$APP_BUNDLE_PATH" ]]; then
  APP_PATHS+=("$APP_BUNDLE_PATH")
fi

for app in $(printf "%s\n" "${APP_PATHS[@]}" | sort -u); do
  if [[ -d "$app" ]]; then
    echo "  Removing app at: $app..."
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$app" 2>/dev/null || true
    rm -rf "$app"
  fi
done

# 8. Reset TCC (Full Disk Access) permissions
echo "[8/8] Resetting privacy / Full Disk Access permissions..."
for u in $(printf "%s\n" "${TARGET_USERS[@]}" | sort -u); do
  sudo -u "$u" tccutil reset SystemPolicyAllFiles top.agata.MacBDEMounter 2>/dev/null || true
  sudo -u "$u" tccutil reset SystemPolicyAllFiles top.agata.BitLockerMounter 2>/dev/null || true
done
tccutil reset SystemPolicyAllFiles top.agata.MacBDEMounter.helper 2>/dev/null || true
tccutil reset SystemPolicyAllFiles top.agata.BitLockerMounter.helper 2>/dev/null || true

echo "=================================================="
echo "  Mac BDE Mounter has been completely uninstalled!"
echo "=================================================="

if [[ -t 0 && -n "${TERM_PROGRAM:-}" ]]; then
  echo ""
  read -n 1 -s -r -p "Press any key to close this window..."
  echo ""
fi
