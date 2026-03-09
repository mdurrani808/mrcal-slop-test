#!/usr/bin/env bash
# Build mrcal itself against the locally-installed deps.
set -euo pipefail
source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/versions.sh"

already_built "mrcal" && exit 0

SRCDIR="$WORK_DIR/mrcal"
git_clone_or_update "$SRCDIR" "https://github.com/dkogan/mrcal.git" "$MRCAL_REF"

cd "$SRCDIR"
ln -sfn "$MRBUILD_MK" "$SRCDIR/mrbuild"

# The mrcal Makefile uses re2c to generate parsers from .re files at build time.
# It also optionally builds a Python extension.  We suppress the Python module
# at install time; we still need python3-dev headers to compile (because some
# mrcal internals reference Python types for the symbol-weakening trick).
#
# If python3-dev is not present the build will fail; in that case either:
#   - Install python3-dev on the host (header-only, not a runtime dep of libmrcal.so), OR
#   - Patch the mrcal Makefile to make Python optional.

export CFLAGS="-I$INSTALL_PREFIX/include"
export CXXFLAGS="-I$INSTALL_PREFIX/include"
export LDFLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib"

make -j"$NPROC" PREFIX="$INSTALL_PREFIX" USE_LIBELAS=0

# Install C library, headers, and CLI tools.
# Skip Python extension — libmrcal.so itself does NOT depend on libpython.so
# (mrcal uses a symbol-weakening trick), so our binary consumers are Python-free.
make install "${MRBUILD_INSTALL_ARGS[@]}" DIST_PY3_MODULES= DIST_PY2_MODULES=

mark_built "mrcal"
log "mrcal installed."
