#!/usr/bin/env bash
# Sourced by all build scripts. Sets up shared env vars and helper functions.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Where sources are cloned / extracted
WORK_DIR="${WORK_DIR:-/tmp/mrcal-build}"

# Where all deps (and mrcal) are installed
INSTALL_PREFIX="${INSTALL_PREFIX:-$REPO_ROOT/install}"

# Parallelism
NPROC="${NPROC:-$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

export PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$INSTALL_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export CMAKE_PREFIX_PATH="$INSTALL_PREFIX:${CMAKE_PREFIX_PATH:-}"
export PATH="$INSTALL_PREFIX/bin:$PATH"

# mrbuild installs its Makefile fragments to $prefix/share/mrbuild by default.
# Point projects at our local mrbuild installation.
export MRBUILD_MK="$INSTALL_PREFIX/share/mrbuild"

log() { echo "==> $*"; }

# Skip a build step if sentinel file already exists.
# Usage: already_built <sentinel_name> && return 0
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

# Clone or update a git repo, then checkout a specific ref.
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
