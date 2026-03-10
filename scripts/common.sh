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

# Operating system — raw uname output: "Linux" or "Darwin".
OS="$(uname -s)"

is_linux() { [[ "$OS" == "Linux" ]]; }
is_macos() { [[ "$OS" == "Darwin" ]]; }

export PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$INSTALL_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export CMAKE_PREFIX_PATH="$INSTALL_PREFIX:${CMAKE_PREFIX_PATH:-}"
export PATH="$INSTALL_PREFIX/bin:$PATH"

# mrbuild installs its Makefile fragments to $prefix/share/mrbuild by default.
# Point projects at our local mrbuild installation.
export MRBUILD_MK="$INSTALL_PREFIX/share/mrbuild"

# Standard args for every mrbuild 'make install'.
#
# DESTDIR=$INSTALL_PREFIX  — install directly into our prefix (non-empty,
#                            satisfies mrbuild's DESTDIR check).
# USRLIB=lib               — override mrbuild's multiarch lib path
#                            (usr/lib/x86_64-linux-gnu on Debian) so .so files
#                            land in $INSTALL_PREFIX/lib/ not /usr/lib/…
# INSTALL_ROOT_BIN/MAN     — strip the /usr prefix from the default paths.
# INSTALL_ROOT_INCLUDE     — preserve the per-project subdir ($(PROJECT_NAME))
#                            but rooted at /include rather than /usr/include.
MRBUILD_INSTALL_ARGS=(
    "DESTDIR=$INSTALL_PREFIX"
    USRLIB=lib
    INSTALL_ROOT_BIN=/bin
    'INSTALL_ROOT_INCLUDE=/include/$(PROJECT_NAME)'
    INSTALL_ROOT_DATA=/share
    INSTALL_ROOT_DOC=/share/doc
    DIST_MAN=       # skip man pages — not shipped and generation can fail
)

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

# Download a source tarball (skips curl if already on disk), then extract it.
# Usage: download_tarball <url> <tarball_path> <extract_dir> [strip_components]
download_tarball() {
    local url="$1" tarball="$2" destdir="$3" strip="${4:-1}"
    if [[ ! -f "$tarball" ]]; then
        log "Downloading $(basename "$tarball")..."
        curl -fsSL "$url" -o "$tarball"
    fi
    mkdir -p "$destdir"
    tar -xf "$tarball" -C "$destdir" --strip-components="$strip"
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

# mrbuild's install step has several post-install operations that use
# $(DESTDIR)/usr/bin/ hardcoded (chrpath, chmod) even when INSTALL_ROOT_BIN
# is overridden to /bin.  Create a usr/bin symlink so those operations find
# the right files without error.
mkdir -p "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/usr"
ln -sfn "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/usr/bin"
