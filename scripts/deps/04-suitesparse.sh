#!/usr/bin/env bash
# Install SuiteSparse (provides CHOLMOD, needed by libdogleg).
#
# Fast path (preferred):
#   Linux  — uses apt if the installed version is ≥ 7 (Ubuntu 24.04+)
#   macOS  — uses Homebrew suite-sparse (always 7.x)
# Slow path (fallback): builds from source.
#
# Ubuntu 22.04 ships SuiteSparse 5.x which is API-incompatible with the
# libdogleg we build; on those systems we always build 7.x from source.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "suitesparse" && exit 0

OS="$(uname -s)"

# ---------------------------------------------------------------------------
# Helper: copy an installed SuiteSparse into INSTALL_PREFIX.
# Arguments: <lib-dir> <include-dir> [cmake-dir]
# ---------------------------------------------------------------------------
install_from_prefix() {
    local libdir="$1" incdir="$2" cmakedir="${3:-}"

    mkdir -p "$INSTALL_PREFIX/lib" "$INSTALL_PREFIX/include"

    # Copy all SuiteSparse shared libs — dereference symlinks.
    for name in libsuitesparseconfig libcholmod libamd libcamd libcolamd libccolamd; do
        find "$libdir" -maxdepth 1 \
            \( -name "${name}.so*" -o -name "${name}.dylib" -o -name "${name}.*.dylib" \) \
            | while read -r f; do
                cp -LRf "$f" "$INSTALL_PREFIX/lib/" 2>/dev/null || cp -Rf "$f" "$INSTALL_PREFIX/lib/"
            done
    done

    # Headers — keep the suitesparse/ subdir that downstream code expects.
    if [[ -d "$incdir/suitesparse" ]]; then
        cp -rn "$incdir/suitesparse" "$INSTALL_PREFIX/include/" 2>/dev/null || true
    fi
    # Some installs put headers directly in include/.
    for h in cholmod.h SuiteSparse_config.h amd.h camd.h colamd.h ccolamd.h; do
        [[ -f "$incdir/$h" ]] && cp -n "$incdir/$h" "$INSTALL_PREFIX/include/" 2>/dev/null || true
    done

    # CMake config files.
    if [[ -n "$cmakedir" && -d "$cmakedir" ]]; then
        mkdir -p "$INSTALL_PREFIX/lib/cmake"
        cp -rn "$cmakedir/." "$INSTALL_PREFIX/lib/cmake/" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Fast path: Linux apt — only if version ≥ 7 (API-compatible with libdogleg)
# ---------------------------------------------------------------------------
if [[ "$OS" == "Linux" ]] && command -v dpkg-query &>/dev/null; then
    SS_VER="$(dpkg-query -W -f='${Version}' libsuitesparse-dev 2>/dev/null || true)"
    # Strip epoch prefix (e.g. "1:7.7.0+dfsg-1" → "7")
    SS_MAJOR="$(echo "$SS_VER" | sed 's/.*://;s/\..*//')"
    if [[ "${SS_MAJOR:-0}" -ge 7 ]]; then
        log "Using system SuiteSparse $SS_VER."
        LIBDIR="$(ldconfig -p 2>/dev/null | awk '/libcholmod\.so /{print $NF}' | head -1 | xargs dirname)"

        CMAKE_DIR=""
        for d in "$LIBDIR/cmake" /usr/lib/cmake /usr/share/cmake; do
            [[ -d "$d/SuiteSparse" ]] && { CMAKE_DIR="$d/SuiteSparse"; break; }
            [[ -d "$d/SuiteSparse_config" ]] && { CMAKE_DIR="$d"; break; }
        done

        install_from_prefix "$LIBDIR" /usr/include "$CMAKE_DIR"
        mark_built "suitesparse"
        log "SuiteSparse installed from system packages."
        exit 0
    else
        log "System SuiteSparse is ${SS_VER:-not installed} (need ≥ 7); building from source."
    fi
fi

# ---------------------------------------------------------------------------
# Fast path: macOS with Homebrew suite-sparse (always provides 7.x)
# ---------------------------------------------------------------------------
if [[ "$OS" == "Darwin" ]] && command -v brew &>/dev/null; then
    if ! brew list suite-sparse &>/dev/null; then
        log "Installing SuiteSparse via Homebrew..."
        brew install suite-sparse
    fi
    BREW_PREFIX="$(brew --prefix suite-sparse)"

    CMAKE_DIR=""
    [[ -d "$BREW_PREFIX/lib/cmake" ]] && CMAKE_DIR="$BREW_PREFIX/lib/cmake"

    install_from_prefix "$BREW_PREFIX/lib" "$BREW_PREFIX/include" "$CMAKE_DIR"
    mark_built "suitesparse"
    log "SuiteSparse installed from Homebrew."
    exit 0
fi

# ---------------------------------------------------------------------------
# Slow path: build from source
# ---------------------------------------------------------------------------
log "Building SuiteSparse $SUITESPARSE_VERSION from source..."

SRCDIR="$WORK_DIR/SuiteSparse"
URL="https://github.com/DrTimothyAldenDavis/SuiteSparse/archive/refs/tags/v$SUITESPARSE_VERSION.tar.gz"
TARBALL="$WORK_DIR/SuiteSparse-$SUITESPARSE_VERSION.tar.gz"

log "Downloading SuiteSparse $SUITESPARSE_VERSION"
curl -fsSL "$URL" -o "$TARBALL"
mkdir -p "$SRCDIR"
tar -xf "$TARBALL" -C "$SRCDIR" --strip-components=1

OPENBLAS_LIB="$INSTALL_PREFIX/lib/libopenblas.so"
if [[ "$OS" == "Darwin" ]]; then
    OPENBLAS_LIB="$INSTALL_PREFIX/lib/libopenblas.dylib"
fi

cd "$SRCDIR"
cmake -B build \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$INSTALL_PREFIX" \
    -DSUITESPARSE_ENABLE_PROJECTS="suitesparse_config;amd;camd;colamd;ccolamd;cholmod" \
    -DSUITESPARSE_USE_CUDA=OFF \
    -DSUITESPARSE_USE_OPENMP=OFF \
    -DSUITESPARSE_USE_FORTRAN=OFF \
    -DCHOLMOD_CAMD=ON \
    -DBLAS_LIBRARIES="$OPENBLAS_LIB" \
    -DLAPACK_LIBRARIES="$OPENBLAS_LIB" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L$INSTALL_PREFIX/lib -lopenblas" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$INSTALL_PREFIX/lib -lopenblas"

cmake --build build -j"$NPROC"
cmake --install build

mark_built "suitesparse"
log "SuiteSparse $SUITESPARSE_VERSION installed."
