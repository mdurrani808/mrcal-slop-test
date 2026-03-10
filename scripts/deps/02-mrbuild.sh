#!/usr/bin/env bash
# Install mrbuild (Make framework used at build time, not bundled in the tarball).
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "mrbuild" && exit 0

SRCDIR="$WORK_DIR/mrbuild"
git_clone_or_update "$SRCDIR" "https://github.com/dkogan/mrbuild.git" "$MRBUILD_REF"

# mrbuild is just Make include files — copy them to where MRBUILD_MK points.
MRBUILD_DEST="$INSTALL_PREFIX/share/mrbuild"
mkdir -p "$MRBUILD_DEST"
cp "$SRCDIR/Makefile.common.header" "$SRCDIR/Makefile.common.footer" "$MRBUILD_DEST/"
cp -r "$SRCDIR/bin" "$MRBUILD_DEST/"

mark_built "mrbuild"
log "mrbuild installed."
