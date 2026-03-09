#!/usr/bin/env bash
# Install mrbuild (Make framework — build-time only, not bundled in tarball).
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "mrbuild" && exit 0

SRCDIR="$WORK_DIR/mrbuild"
git_clone_or_update "$SRCDIR" "https://github.com/dkogan/mrbuild.git" "$MRBUILD_REF"

cd "$SRCDIR"
# mrbuild installs its Make include files; no compilation needed.
make install PREFIX="$INSTALL_PREFIX"

mark_built "mrbuild"
log "mrbuild installed."
