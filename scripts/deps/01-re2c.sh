#!/usr/bin/env bash
# Install re2c (parser generator — build-time tool only, not bundled in tarball).
#
# Fast path: use whatever re2c is already in PATH (apt/brew installs land there).
# Slow path: build from source.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "re2c" && exit 0

OS="$(uname -s)"

# ---------------------------------------------------------------------------
# Fast path: re2c already available (system apt or brew install)
# ---------------------------------------------------------------------------
if command -v re2c &>/dev/null; then
    log "Using system re2c ($(re2c --version | head -1))."
    mark_built "re2c"
    exit 0
fi

# ---------------------------------------------------------------------------
# Fast path: install via package manager
# ---------------------------------------------------------------------------
if [[ "$OS" == "Linux" ]] && command -v apt-get &>/dev/null; then
    log "Installing re2c via apt..."
    apt-get install -y --no-install-recommends re2c
    mark_built "re2c"
    log "re2c installed from apt."
    exit 0
fi

if [[ "$OS" == "Darwin" ]] && command -v brew &>/dev/null; then
    log "Installing re2c via Homebrew..."
    brew install re2c
    mark_built "re2c"
    log "re2c installed from Homebrew."
    exit 0
fi

# ---------------------------------------------------------------------------
# Slow path: build from source
# ---------------------------------------------------------------------------
log "Building re2c $RE2C_VERSION from source..."

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
