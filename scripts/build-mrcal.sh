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
        brew install cpanminus
        for attempt in 1 2 3; do
            cpanm --notest List::MoreUtils && break
            echo "cpanm attempt $attempt failed, retrying..." >&2
            sleep 5
        done
    fi
fi

# mrcal references Python types internally (symbol weakening), so python3-dev
# headers are needed at compile time even though we don't ship the Python module.
NUMPY_INC="$(python3 -c 'import numpy; print(numpy.get_include())' 2>/dev/null || true)"

# numpysane (build-time code generator) needs setuptools as a distutils shim on Python 3.12+.
if ! python3 -c 'import numpysane' 2>/dev/null; then
    # --break-system-packages is required on PEP 668 systems (macOS, Ubuntu 24.04+).
    python3 -m pip install --quiet --break-system-packages setuptools numpysane 2>/dev/null \
        || python3 -m pip install --quiet setuptools numpysane
fi

# On macOS, libpng and libjpeg aren't in the default search path — pull them from Homebrew.
IMG_CFLAGS=""
IMG_LDFLAGS=""
if is_macos && command -v brew &>/dev/null; then
    for pkg in libpng jpeg jpeg-turbo; do
        prefix="$(brew --prefix "$pkg" 2>/dev/null || true)"
        if [[ -n "$prefix" && -d "$prefix/include" ]]; then
            IMG_CFLAGS="$IMG_CFLAGS -I$prefix/include"
            IMG_LDFLAGS="$IMG_LDFLAGS -L$prefix/lib"
        fi
    done
fi

# No stb formula on Homebrew — download the headers directly.
STB_INC=""
if is_macos; then
    STB_INC="$INSTALL_PREFIX/include/stb"
    if [[ ! -f "$STB_INC/stb_image.h" ]]; then
        mkdir -p "$STB_INC"
        curl -fsSL "https://raw.githubusercontent.com/nothings/stb/master/stb_image.h" \
            -o "$STB_INC/stb_image.h"
        curl -fsSL "https://raw.githubusercontent.com/nothings/stb/master/stb_image_write.h" \
            -o "$STB_INC/stb_image_write.h"
    fi
fi

export CFLAGS="-I$INSTALL_PREFIX/include${NUMPY_INC:+ -I$NUMPY_INC}${STB_INC:+ -I$STB_INC}${IMG_CFLAGS:+ $IMG_CFLAGS}"
export CXXFLAGS="-I$INSTALL_PREFIX/include${NUMPY_INC:+ -I$NUMPY_INC}${STB_INC:+ -I$STB_INC}${IMG_CFLAGS:+ $IMG_CFLAGS}"
export LDFLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib${IMG_LDFLAGS:+ $IMG_LDFLAGS}"

make -j"$NPROC" PREFIX="$INSTALL_PREFIX" USE_LIBELAS=

# Install C lib + headers + CLI tools; skip Python extension.
make install "${MRBUILD_INSTALL_ARGS[@]}" DIST_PY3_MODULES= DIST_PY2_MODULES=

mark_built "mrcal"
log "mrcal installed."
