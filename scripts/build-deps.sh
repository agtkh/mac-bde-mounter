#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Fetch and build the third-party binaries that are bundled inside
# MacBDEMounter.app (Standalone distribution):
#
#   * FUSE-T   – extracted from the official pkg (NOT installed on this Mac)
#   * mbedTLS  – built as static libraries (used under GPL-2.0-or-later)
#   * dislocker – built against FUSE-T's libfuse3 (static) + mbedTLS (static)
#
# Output: vendor/dist/bin/
#   dislocker             (dislocker-fuse, links @rpath/libdislocker.dylib)
#   libdislocker.dylib
#   fuse-t/go-nfsv4       (deployed by the privileged helper on first run)
#   fuse-t/LICENSE.rtf
#
# Requirements: Xcode (or CLT), cmake, pkg-config, curl, shasum.
set -euo pipefail

FUSE_T_VERSION="1.2.7"
FUSE_T_SHA256="6a29c747e61a86a405a189efc3de42812d73147135f93a1bb0624c1e7b90e654"
FUSE_T_URL="https://github.com/macos-fuse-t/fuse-t/releases/download/${FUSE_T_VERSION}/fuse-t-macos-installer-${FUSE_T_VERSION}.pkg"

MBEDTLS_VERSION="3.6.7"
MBEDTLS_SHA256="a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6"
MBEDTLS_URL="https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-${MBEDTLS_VERSION}/mbedtls-${MBEDTLS_VERSION}.tar.bz2"

DISLOCKER_COMMIT="0706462db88efe8df88150e4c3e4332b808f4581"
DISLOCKER_SHA256="e48061012aafac5c5f37e453e91a1dc94bd32af67e9313d17689c7935bb07b57"
DISLOCKER_URL="https://github.com/Aorimn/dislocker/archive/${DISLOCKER_COMMIT}.tar.gz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="${ROOT}/vendor"
DL="${VENDOR}/downloads"
SRC="${VENDOR}/src"
PREFIX="${VENDOR}/prefix"
DIST="${VENDOR}/dist/bin"
ARCH="${ARCH:-arm64}"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
export MACOSX_DEPLOYMENT_TARGET
JOBS="$(sysctl -n hw.ncpu)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

fetch() { # url sha256 dest
  local url="$1" sum="$2" dest="$3"
  if [[ ! -f "$dest" ]]; then
    log "Downloading $(basename "$dest")"
    curl -fsSL --retry 3 -o "${dest}.part" "$url"
    mv "${dest}.part" "$dest"
  fi
  echo "${sum}  ${dest}" | shasum -a 256 -c - >/dev/null || {
    echo "Checksum mismatch for ${dest}" >&2; rm -f "$dest"; exit 1; }
}

mkdir -p "$DL" "$SRC" "$PREFIX" "$DIST"

# ---------------------------------------------------------------- FUSE-T
fetch "$FUSE_T_URL" "$FUSE_T_SHA256" "${DL}/fuse-t-${FUSE_T_VERSION}.pkg"
FUSE_T_DIR="${SRC}/fuse-t-${FUSE_T_VERSION}"
if [[ ! -d "$FUSE_T_DIR" ]]; then
  log "Extracting FUSE-T pkg (no installation)"
  pkgutil --expand-full "${DL}/fuse-t-${FUSE_T_VERSION}.pkg" "$FUSE_T_DIR"
fi
FUSE_T_PAYLOAD="${FUSE_T_DIR}/fuse-t-core.pkg/Payload/Library/Application Support/fuse-t"
FUSE_PREFIX="${PREFIX}/fuse-t"
rm -rf "$FUSE_PREFIX"; mkdir -p "${FUSE_PREFIX}/lib/pkgconfig" "${FUSE_PREFIX}/include"
cp -R "${FUSE_T_PAYLOAD}/include/fuse3" "${FUSE_PREFIX}/include/"
# Thin the static lib to the target arch so the linker never picks a dylib.
lipo "${FUSE_T_PAYLOAD}/lib/libfuse3.a" -thin "$ARCH" -output "${FUSE_PREFIX}/lib/libfuse3.a"
cat > "${FUSE_PREFIX}/lib/pkgconfig/fuse3.pc" <<EOF
prefix=${FUSE_PREFIX}
libdir=\${prefix}/lib
includedir=\${prefix}/include/fuse3

Name: fuse3
Description: FUSE-T libfuse3 (static, bundled)
Version: ${FUSE_T_VERSION}
Libs: -L\${libdir} -lfuse3 -framework CoreFoundation -framework DiskArbitration
Cflags: -I\${includedir}
EOF

# ---------------------------------------------------------------- mbedTLS
fetch "$MBEDTLS_URL" "$MBEDTLS_SHA256" "${DL}/mbedtls-${MBEDTLS_VERSION}.tar.bz2"
MBED_SRC="${SRC}/mbedtls-${MBEDTLS_VERSION}"
if [[ ! -f "${PREFIX}/mbedtls/lib/libmbedcrypto.a" ]]; then
  rm -rf "$MBED_SRC"; tar -xjf "${DL}/mbedtls-${MBEDTLS_VERSION}.tar.bz2" -C "$SRC"
  log "Building mbedTLS ${MBEDTLS_VERSION} (static)"
  cmake -S "$MBED_SRC" -B "${MBED_SRC}/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}/mbedtls" \
    -DUSE_STATIC_MBEDTLS_LIBRARY=ON -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
    -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF >/dev/null
  cmake --build "${MBED_SRC}/build" -j "$JOBS" >/dev/null
  cmake --install "${MBED_SRC}/build" >/dev/null
fi

# ---------------------------------------------------------------- dislocker
fetch "$DISLOCKER_URL" "$DISLOCKER_SHA256" "${DL}/dislocker-${DISLOCKER_COMMIT}.tar.gz"
DIS_SRC="${SRC}/dislocker-${DISLOCKER_COMMIT}"
rm -rf "$DIS_SRC"; tar -xzf "${DL}/dislocker-${DISLOCKER_COMMIT}.tar.gz" -C "$SRC"
if compgen -G "${ROOT}/scripts/patches/dislocker/*.patch" >/dev/null; then
  for p in "${ROOT}"/scripts/patches/dislocker/*.patch; do
    log "Applying $(basename "$p")"
    patch -d "$DIS_SRC" -p1 < "$p"
  done
fi
log "Building dislocker (${DISLOCKER_COMMIT:0:7})"
PKG_CONFIG_PATH="${FUSE_PREFIX}/lib/pkgconfig" PKG_CONFIG_LIBDIR="${FUSE_PREFIX}/lib/pkgconfig" \
cmake -S "$DIS_SRC" -B "${DIS_SRC}/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  -DCMAKE_PREFIX_PATH="${PREFIX}/mbedtls" \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}/dislocker" \
  -DCMAKE_INSTALL_NAME_DIR="@rpath" \
  -DCMAKE_INSTALL_RPATH="@executable_path" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  -DWITH_RUBY=OFF -DWITH_FUSE=ON
cmake --build "${DIS_SRC}/build" -j "$JOBS"
rm -rf "${PREFIX}/dislocker"
cmake --install "${DIS_SRC}/build"

# ---------------------------------------------------------------- dist
log "Assembling ${DIST}"
rm -rf "$DIST"; mkdir -p "${DIST}/fuse-t"
cp "${PREFIX}/dislocker/bin/dislocker-fuse" "${DIST}/dislocker"
LIBDIS="$(find "${PREFIX}/dislocker" -name 'libdislocker*.dylib' -type f | head -1)"
cp "$LIBDIS" "${DIST}/libdislocker.dylib"
install_name_tool -id "@rpath/libdislocker.dylib" "${DIST}/libdislocker.dylib"
# Rewrite whatever versioned name dislocker was linked against.
OLD="$(otool -L "${DIST}/dislocker" | awk '/libdislocker/ {print $1}')"
[[ -n "$OLD" ]] && install_name_tool -change "$OLD" "@rpath/libdislocker.dylib" "${DIST}/dislocker"
# Strip any build-time rpaths, keep only @executable_path.
otool -l "${DIST}/dislocker" | awk '/LC_RPATH/{f=1} f&&/path /{print $2; f=0}' | while read -r rp; do
  install_name_tool -delete_rpath "$rp" "${DIST}/dislocker" 2>/dev/null || true
done
install_name_tool -add_rpath "@executable_path" "${DIST}/dislocker"

lipo "${FUSE_T_PAYLOAD}/bin/go-nfsv4-${FUSE_T_VERSION}" -thin "$ARCH" -output "${DIST}/fuse-t/go-nfsv4" \
  || cp "${FUSE_T_PAYLOAD}/bin/go-nfsv4-${FUSE_T_VERSION}" "${DIST}/fuse-t/go-nfsv4"
chmod 755 "${DIST}/fuse-t/go-nfsv4"
mkdir -p "${VENDOR}/dist/resources/fuse-t"
cp "${FUSE_T_PAYLOAD}/LICENSE.rtf" "${VENDOR}/dist/resources/fuse-t/LICENSE.rtf"
echo "${FUSE_T_VERSION}" > "${VENDOR}/dist/resources/fuse-t/VERSION"

# Re-sign ad-hoc after install_name_tool (signature is replaced in sign.sh).
codesign --force --sign - "${DIST}/libdislocker.dylib" "${DIST}/dislocker" "${DIST}/fuse-t/go-nfsv4" 2>/dev/null

log "Linkage check"
otool -L "${DIST}/dislocker" "${DIST}/libdislocker.dylib"
if otool -L "${DIST}/dislocker" "${DIST}/libdislocker.dylib" | grep -v ':$' | grep -E '/usr/local|/opt/homebrew|/vendor/' ; then
  echo "ERROR: non-relocatable dependency detected" >&2; exit 1
fi
log "Done: ${DIST}"
