#!/usr/bin/env bash
# Build libdogleg (dog-leg optimizer, core mrcal dependency).
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "libdogleg" && exit 0

SRCDIR="$WORK_DIR/libdogleg"
git_clone_or_update "$SRCDIR" "https://github.com/dkogan/libdogleg.git" "$LIBDOGLEG_REF"

cd "$SRCDIR"

# choose_mrbuild.mk looks for a local 'mrbuild/' directory first — symlink ours.
ln -sfn "$MRBUILD_MK" "$SRCDIR/mrbuild"

export CFLAGS="-I$INSTALL_PREFIX/include"
export LDFLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib"

make -j"$NPROC" PREFIX="$INSTALL_PREFIX"
make install "${MRBUILD_INSTALL_ARGS[@]}" INSTALL_ROOT_INCLUDE=/include

mark_built "libdogleg"
log "libdogleg installed."
