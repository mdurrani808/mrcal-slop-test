#!/usr/bin/env bash
# Build SuiteSparse (provides CHOLMOD, needed by libdogleg).
# Only the components we need: SuiteSparse_config, AMD, CAMD, COLAMD, CCOLAMD, CHOLMOD.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "suitesparse" && exit 0

SRCDIR="$WORK_DIR/SuiteSparse"
URL="https://github.com/DrTimothyAldenDavis/SuiteSparse/archive/refs/tags/v$SUITESPARSE_VERSION.tar.gz"
TARBALL="$WORK_DIR/SuiteSparse-$SUITESPARSE_VERSION.tar.gz"

log "Downloading SuiteSparse $SUITESPARSE_VERSION"
curl -fsSL "$URL" -o "$TARBALL"
mkdir -p "$SRCDIR"
tar -xf "$TARBALL" -C "$SRCDIR" --strip-components=1

OPENBLAS_LIB="$INSTALL_PREFIX/lib/libopenblas.so"
if [[ "$(uname -s)" == "Darwin" ]]; then
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
