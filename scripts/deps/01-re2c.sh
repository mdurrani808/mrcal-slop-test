#!/usr/bin/env bash
# Install re2c (parser generator used at build time, not bundled in the tarball).
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "re2c" && exit 0

# Fast path: already in PATH
if command -v re2c &>/dev/null; then
    log "Using system re2c ($(re2c --version | head -1))."
    mark_built "re2c"
    exit 0
fi

# Fast path: install via package manager
if is_linux && command -v apt-get &>/dev/null; then
    log "Installing re2c via apt..."
    apt-get install -y --no-install-recommends re2c
    mark_built "re2c"
    log "re2c installed from apt."
    exit 0
fi

if is_macos && command -v brew &>/dev/null; then
    log "Installing re2c via Homebrew..."
    brew install re2c
    mark_built "re2c"
    log "re2c installed from Homebrew."
    exit 0
fi

# Slow path: build from source
log "Building re2c $RE2C_VERSION from source..."

SRCDIR="$WORK_DIR/re2c"
URL="https://github.com/skvadrik/re2c/releases/download/$RE2C_VERSION/re2c-$RE2C_VERSION.tar.xz"
TARBALL="$WORK_DIR/re2c-$RE2C_VERSION.tar.xz"
download_tarball "$URL" "$TARBALL" "$SRCDIR"

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
