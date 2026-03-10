#!/usr/bin/env bash
# Sourced by all build scripts. Sets up shared env vars and helper functions.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Where sources are cloned / extracted
WORK_DIR="${WORK_DIR:-/tmp/mrcal-build}"

# Where all deps (and mrcal) are installed
INSTALL_PREFIX="${INSTALL_PREFIX:-$REPO_ROOT/install}"

NPROC="${NPROC:-$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

OS="$(uname -s)"

is_linux() { [[ "$OS" == "Linux" ]]; }
is_macos() { [[ "$OS" == "Darwin" ]]; }

export PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$INSTALL_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export CMAKE_PREFIX_PATH="$INSTALL_PREFIX:${CMAKE_PREFIX_PATH:-}"
export PATH="$INSTALL_PREFIX/bin:$PATH"

export MRBUILD_MK="$INSTALL_PREFIX/share/mrbuild"

# Shared args for all mrbuild 'make install' calls. Keeps everything under
# $INSTALL_PREFIX with flat lib/ and bin/ dirs instead of Debian multiarch paths.
MRBUILD_INSTALL_ARGS=(
    "DESTDIR=$INSTALL_PREFIX"
    USRLIB=lib
    INSTALL_ROOT_BIN=/bin
    'INSTALL_ROOT_INCLUDE=/include/$(PROJECT_NAME)'
    INSTALL_ROOT_DATA=/share
    INSTALL_ROOT_DOC=/share/doc
    DIST_MAN=       # skip man pages
)

log() { echo "==> $*"; }

# Usage: already_built <name> && exit 0
already_built() {
    local sentinel="$WORK_DIR/.built_$1"
    if [[ -f "$sentinel" ]]; then
        log "$1 already built, skipping."
        return 0
    fi
    return 1
}

mark_built() {
    touch "$WORK_DIR/.built_$1"
}

# Usage: download_tarball <url> <tarball_path> <extract_dir> [strip_components]
download_tarball() {
    local url="$1" tarball="$2" destdir="$3" strip="${4:-1}"
    if [[ ! -f "$tarball" ]]; then
        log "Downloading $(basename "$tarball")..."
        local downloaded=0
        for attempt in 1 2 3; do
            if curl -fsSL "$url" -o "$tarball"; then
                downloaded=1
                break
            fi
            echo "Download attempt $attempt failed for $(basename "$tarball"), retrying..." >&2
            rm -f "$tarball"
            sleep 5
        done
        if [[ $downloaded -eq 0 ]]; then
            echo "ERROR: Failed to download $(basename "$tarball") after 3 attempts." >&2
            exit 1
        fi
    fi
    mkdir -p "$destdir"
    tar -xf "$tarball" -C "$destdir" --strip-components="$strip"
}

# Usage: git_clone_or_update <dir> <url> <ref>
git_clone_or_update() {
    local dir="$1" url="$2" ref="$3"
    if [[ -d "$dir/.git" ]]; then
        log "Updating $dir"
        git -C "$dir" fetch --quiet origin
    else
        log "Cloning $url into $dir"
        git clone --quiet "$url" "$dir"
    fi
    git -C "$dir" checkout --quiet "$ref"
}

mkdir -p "$WORK_DIR" "$INSTALL_PREFIX"

# mrbuild hardcodes $(DESTDIR)/usr/bin in some post-install steps even when
# INSTALL_ROOT_BIN is overridden — symlink it so those steps don't fail.
mkdir -p "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/usr"
ln -sfn "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/usr/bin"
