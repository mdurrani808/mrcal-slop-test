#!/usr/bin/env bash
# Build mrgingham (chessboard corner finder, needed by mrcal).
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "mrgingham" && exit 0

SRCDIR="$WORK_DIR/mrgingham"
git_clone_or_update "$SRCDIR" "https://github.com/dkogan/mrgingham.git" "$MRGINGHAM_REF"

cd "$SRCDIR"
ln -sfn "$MRBUILD_MK" "$SRCDIR/mrbuild"
make -j"$NPROC" \
    PREFIX="$INSTALL_PREFIX" \
    MRBUILD_MK="$MRBUILD_MK" \
    CFLAGS="-I$INSTALL_PREFIX/include" \
    CXXFLAGS="-I$INSTALL_PREFIX/include" \
    LDFLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib"

# Install C++ library + headers + CLI tools; skip Python module.
make install \
    PREFIX="$INSTALL_PREFIX" \
    MRBUILD_MK="$MRBUILD_MK" \
    DIST_PY3_MODULES= \
    DIST_PY2_MODULES=

mark_built "mrgingham"
log "mrgingham installed."
