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

# minimath_generate.pl requires List::MoreUtils.
if ! perl -MList::MoreUtils -e1 2>/dev/null; then
    if command -v apt-get &>/dev/null; then
        apt-get install -y --no-install-recommends liblist-moreutils-perl
    elif command -v brew &>/dev/null; then
        brew install cpanminus && cpanm --notest List::MoreUtils
    fi
fi

# The mrcal Makefile uses re2c to generate parsers from .re files at build time.
# It also optionally builds a Python extension.  We suppress the Python module
# at install time; we still need python3-dev headers to compile (because some
# mrcal internals reference Python types for the symbol-weakening trick).
#
# If python3-dev is not present the build will fail; in that case either:
#   - Install python3-dev on the host (header-only, not a runtime dep of libmrcal.so), OR
#   - Patch the mrcal Makefile to make Python optional.

NUMPY_INC="$(python3 -c 'import numpy; print(numpy.get_include())' 2>/dev/null || true)"

# numpysane is required by mrcal-genpywrap.py at build time.
if ! python3 -c 'import numpysane' 2>/dev/null; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
        python3 -m pip install --quiet --break-system-packages numpysane
    else
        python3 -m pip install --quiet numpysane
    fi
fi

# stb_image.h — on macOS brew has no 'stb' formula; download the header directly.
STB_INC=""
if [[ "$(uname -s)" == "Darwin" ]]; then
    STB_INC="$INSTALL_PREFIX/include/stb"
    if [[ ! -f "$STB_INC/stb_image.h" ]]; then
        mkdir -p "$STB_INC"
        curl -fsSL "https://raw.githubusercontent.com/nothings/stb/master/stb_image.h" \
            -o "$STB_INC/stb_image.h"
        curl -fsSL "https://raw.githubusercontent.com/nothings/stb/master/stb_image_write.h" \
            -o "$STB_INC/stb_image_write.h"
    fi
fi

export CFLAGS="-I$INSTALL_PREFIX/include${NUMPY_INC:+ -I$NUMPY_INC}${STB_INC:+ -I$STB_INC}"
export CXXFLAGS="-I$INSTALL_PREFIX/include${NUMPY_INC:+ -I$NUMPY_INC}${STB_INC:+ -I$STB_INC}"
export LDFLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib"

make -j"$NPROC" PREFIX="$INSTALL_PREFIX" USE_LIBELAS=

# Install C library, headers, and CLI tools.
# Skip Python extension — libmrcal.so itself does NOT depend on libpython.so
# (mrcal uses a symbol-weakening trick), so our binary consumers are Python-free.
make install "${MRBUILD_INSTALL_ARGS[@]}" DIST_PY3_MODULES= DIST_PY2_MODULES=

mark_built "mrcal"
log "mrcal installed."
