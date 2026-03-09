#!/usr/bin/env bash
# Build OpenBLAS (provides BLAS + LAPACK, needed by SuiteSparse → libdogleg).
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "openblas" && exit 0

SRCDIR="$WORK_DIR/OpenBLAS"
URL="https://github.com/OpenMathLib/OpenBLAS/releases/download/v$OPENBLAS_VERSION/OpenBLAS-$OPENBLAS_VERSION.tar.gz"
TARBALL="$WORK_DIR/OpenBLAS-$OPENBLAS_VERSION.tar.gz"

log "Downloading OpenBLAS $OPENBLAS_VERSION"
curl -fsSL "$URL" -o "$TARBALL"
mkdir -p "$SRCDIR"
tar -xf "$TARBALL" -C "$SRCDIR" --strip-components=1

# Detect whether we're on macOS (Darwin).
OS="$(uname -s)"

EXTRA_FLAGS=""
if [[ "$OS" == "Darwin" ]]; then
    # On Apple Silicon don't try to probe all CPU variants.
    EXTRA_FLAGS="DYNAMIC_ARCH=0"
else
    # On Linux let it pick the best implementation at runtime.
    EXTRA_FLAGS="DYNAMIC_ARCH=1"
fi

cd "$SRCDIR"
# Build LAPACK support too (needed by SuiteSparse/CHOLMOD).
make -j"$NPROC" \
    PREFIX="$INSTALL_PREFIX" \
    NO_LAPACKE=0 \
    BUILD_LAPACK_DEPRECATED=1 \
    USE_THREAD=1 \
    $EXTRA_FLAGS

make install PREFIX="$INSTALL_PREFIX" $EXTRA_FLAGS

mark_built "openblas"
log "OpenBLAS $OPENBLAS_VERSION installed."
