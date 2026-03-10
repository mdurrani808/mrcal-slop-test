#!/usr/bin/env bash
# Install OpenBLAS (provides BLAS + LAPACK, needed by SuiteSparse → libdogleg).
#
# Fast path (preferred):
#   Linux  — copies the system libopenblas-dev into INSTALL_PREFIX
#   macOS  — copies the Homebrew openblas into INSTALL_PREFIX
# Slow path (fallback): builds from source.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "openblas" && exit 0

# ---------------------------------------------------------------------------
# Helper: copy an installed openblas into INSTALL_PREFIX.
# Arguments: <lib-dir> <include-dir>
# ---------------------------------------------------------------------------
install_from_prefix() {
    local libdir="$1" incdir="$2"

    mkdir -p "$INSTALL_PREFIX/lib" "$INSTALL_PREFIX/include"

    # Copy all libopenblas* — dereference symlinks so we get real files.
    find "$libdir" -maxdepth 1 -name 'libopenblas*' | while read -r f; do
        cp -LRf "$f" "$INSTALL_PREFIX/lib/"
    done

    # Copy headers.
    if [[ -d "$incdir/openblas" ]]; then
        cp -rn "$incdir/openblas/." "$INSTALL_PREFIX/include/openblas/"
    fi
    for h in cblas.h lapack.h lapacke.h lapacke_config.h; do
        [[ -f "$incdir/$h" ]] && cp -n "$incdir/$h" "$INSTALL_PREFIX/include/" || true
    done

    # Write a minimal pkgconfig so downstream projects find libs in INSTALL_PREFIX.
    mkdir -p "$INSTALL_PREFIX/lib/pkgconfig"
    cat > "$INSTALL_PREFIX/lib/pkgconfig/openblas.pc" <<EOF
prefix=${INSTALL_PREFIX}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: OpenBLAS
Description: OpenBLAS is an optimized BLAS library
Version: ${OPENBLAS_VERSION}
Libs: -L\${libdir} -lopenblas
Cflags: -I\${includedir}
EOF
}

# ---------------------------------------------------------------------------
# Fast path: Linux with a system-installed libopenblas (e.g. apt libopenblas-dev)
# ---------------------------------------------------------------------------
if [[ "$OS" == "Linux" ]]; then
    # ldconfig -p is always available and doesn't require pkg-config.
    LIBOPENBLAS="$(ldconfig -p 2>/dev/null | awk '/libopenblas\.so /{print $NF}' | head -1)"
    if [[ -n "$LIBOPENBLAS" ]]; then
        log "Using system OpenBLAS at $LIBOPENBLAS"
        LIBDIR="$(dirname "$LIBOPENBLAS")"
        # Find the header directory.
        INCDIR=/usr/include
        for d in /usr/include/openblas /usr/include/x86_64-linux-gnu /usr/include/aarch64-linux-gnu; do
            [[ -f "$d/cblas.h" ]] && { INCDIR="$d"; break; }
        done
        install_from_prefix "$LIBDIR" "$INCDIR"
        mark_built "openblas"
        log "OpenBLAS installed from system packages."
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Fast path: macOS with Homebrew openblas
# ---------------------------------------------------------------------------
if [[ "$OS" == "Darwin" ]] && command -v brew &>/dev/null; then
    if ! brew list openblas &>/dev/null; then
        log "Installing OpenBLAS via Homebrew..."
        brew install openblas
    fi
    BREW_PREFIX="$(brew --prefix openblas)"
    install_from_prefix "$BREW_PREFIX/lib" "$BREW_PREFIX/include"

    # Homebrew's pkgconfig may not be on PKG_CONFIG_PATH yet; write one ourselves.
    if [[ -f "$BREW_PREFIX/lib/pkgconfig/openblas.pc" ]]; then
        mkdir -p "$INSTALL_PREFIX/lib/pkgconfig"
        sed \
            -e "s|${BREW_PREFIX}/lib|${INSTALL_PREFIX}/lib|g" \
            -e "s|${BREW_PREFIX}/include|${INSTALL_PREFIX}/include|g" \
            "$BREW_PREFIX/lib/pkgconfig/openblas.pc" \
            > "$INSTALL_PREFIX/lib/pkgconfig/openblas.pc"
    fi

    mark_built "openblas"
    log "OpenBLAS installed from Homebrew."
    exit 0
fi

# ---------------------------------------------------------------------------
# Slow path: build from source
# ---------------------------------------------------------------------------
log "No pre-built OpenBLAS found. Building from source (this will take a while)..."

SRCDIR="$WORK_DIR/OpenBLAS"
URL="https://github.com/OpenMathLib/OpenBLAS/releases/download/v$OPENBLAS_VERSION/OpenBLAS-$OPENBLAS_VERSION.tar.gz"
TARBALL="$WORK_DIR/OpenBLAS-$OPENBLAS_VERSION.tar.gz"
download_tarball "$URL" "$TARBALL" "$SRCDIR"

EXTRA_FLAGS=""
if [[ "$OS" == "Darwin" ]]; then
    EXTRA_FLAGS="DYNAMIC_ARCH=0"
else
    EXTRA_FLAGS="DYNAMIC_ARCH=1"
fi

cd "$SRCDIR"
make -j"$NPROC" \
    PREFIX="$INSTALL_PREFIX" \
    NO_LAPACKE=0 \
    BUILD_LAPACK_DEPRECATED=1 \
    USE_THREAD=1 \
    QUIET_MAKE=1 \
    $EXTRA_FLAGS

make install PREFIX="$INSTALL_PREFIX" QUIET_MAKE=1 $EXTRA_FLAGS

mark_built "openblas"
log "OpenBLAS $OPENBLAS_VERSION installed."
