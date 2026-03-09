#!/usr/bin/env bash
# Build libdogleg (dog-leg optimizer, core mrcal dep).
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "libdogleg" && exit 0

SRCDIR="$WORK_DIR/libdogleg"
git_clone_or_update "$SRCDIR" "https://github.com/dkogan/libdogleg.git" "$LIBDOGLEG_REF"

cd "$SRCDIR"

# choose_mrbuild.mk (included by the project Makefile) looks for a local
# 'mrbuild/' directory first. Symlink our installed copy so it finds it.
ln -sfn "$MRBUILD_MK" "$SRCDIR/mrbuild"

make -j"$NPROC" \
    PREFIX="$INSTALL_PREFIX" \
    MRBUILD_MK="$MRBUILD_MK" \
    CFLAGS="-I$INSTALL_PREFIX/include" \
    LDFLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib"

make install \
    PREFIX="$INSTALL_PREFIX" \
    MRBUILD_MK="$MRBUILD_MK"

mark_built "libdogleg"
log "libdogleg installed."
