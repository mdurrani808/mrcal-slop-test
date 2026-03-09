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

# Boost headers are needed for voronoi tessellation (boost/polygon/voronoi.hpp).
# On macOS they aren't in a standard search path, so locate them via brew.
BOOST_INC=""
if [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
    if ! brew list boost &>/dev/null; then
        brew install boost
    fi
    BOOST_INC="$(brew --prefix boost)/include"
fi

export CFLAGS="-I$INSTALL_PREFIX/include${BOOST_INC:+ -I$BOOST_INC}"
export CXXFLAGS="-I$INSTALL_PREFIX/include${BOOST_INC:+ -I$BOOST_INC}"
export LDFLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib"

make -j"$NPROC" PREFIX="$INSTALL_PREFIX"

# Install C++ library + headers + CLI tools; skip Python module.
make install "${MRBUILD_INSTALL_ARGS[@]}" DIST_PY3_MODULES= DIST_PY2_MODULES=

mark_built "mrgingham"
log "mrgingham installed."
