#!/usr/bin/env bash
# Build re2c (parser generator — build-time tool only, not bundled in tarball).
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "re2c" && exit 0

SRCDIR="$WORK_DIR/re2c"
URL="https://github.com/skvadrik/re2c/releases/download/$RE2C_VERSION/re2c-$RE2C_VERSION.tar.xz"
TARBALL="$WORK_DIR/re2c-$RE2C_VERSION.tar.xz"

log "Downloading re2c $RE2C_VERSION"
curl -fsSL "$URL" -o "$TARBALL"
mkdir -p "$SRCDIR"
tar -xf "$TARBALL" -C "$SRCDIR" --strip-components=1

mkdir -p "$SRCDIR/build"
cd "$SRCDIR/build"
cmake .. \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DRE2C_BUILD_RE2GO=OFF \
    -DRE2C_BUILD_RE2RUST=OFF
make -j"$NPROC"
make install

mark_built "re2c"
log "re2c $RE2C_VERSION installed."
