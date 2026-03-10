#!/usr/bin/env bash
# Build and run the C++ smoketest against a mrcal package tarball.
#
# Usage:
#   smoketest.sh <path-to-tarball.tar.gz>
#   smoketest.sh <path-to-already-extracted-mrcal-dir>
#
# The script extracts the tarball (if needed), configures the smoketest with
# CMake using the extracted package, builds it, and runs it.
set -euo pipefail
source "$(dirname "$0")/common.sh"

TARBALL_OR_DIR="${1:-}"
if [[ -z "$TARBALL_OR_DIR" ]]; then
    # Default: pick the first tarball from the standard artifacts directory.
    TARBALL_OR_DIR="$(ls "$REPO_ROOT/artifacts/"*.tar.gz 2>/dev/null | head -1 || true)"
fi
if [[ -z "$TARBALL_OR_DIR" ]]; then
    echo "Usage: $0 <tarball.tar.gz | extracted-mrcal-dir>" >&2
    exit 1
fi

BUILD_DIR="/tmp/mrcal-smoketest-build"
EXTRACT_DIR="/tmp/mrcal-smoketest-extract"

# Resolve the mrcal prefix directory.
if [[ -f "$TARBALL_OR_DIR" ]]; then
    log "Extracting $TARBALL_OR_DIR ..."
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    tar -xzf "$TARBALL_OR_DIR" -C "$EXTRACT_DIR"
    MRCAL_PREFIX="$(ls -d "$EXTRACT_DIR"/mrcal-*/)"
elif [[ -d "$TARBALL_OR_DIR" ]]; then
    MRCAL_PREFIX="$TARBALL_OR_DIR"
else
    echo "ERROR: '$TARBALL_OR_DIR' is not a file or directory" >&2
    exit 1
fi

log "Testing package: $MRCAL_PREFIX"

rm -rf "$BUILD_DIR"
cmake -B "$BUILD_DIR" \
    -DCMAKE_PREFIX_PATH="$MRCAL_PREFIX" \
    "$REPO_ROOT/tests"
cmake --build "$BUILD_DIR"

# Run with the library path pointing at the bundled libs so the binary can
# find them regardless of where it was installed.
if is_linux; then
    LD_LIBRARY_PATH="$MRCAL_PREFIX/lib" "$BUILD_DIR/smoketest"
elif is_macos; then
    DYLD_LIBRARY_PATH="$MRCAL_PREFIX/lib" "$BUILD_DIR/smoketest"
else
    "$BUILD_DIR/smoketest"
fi

log "Smoketest PASSED"
