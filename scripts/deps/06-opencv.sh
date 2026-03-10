#!/usr/bin/env bash
# Install OpenCV (needed by mrgingham).
#
# Fast path (preferred):
#   Linux  — copies the system libopencv-dev into INSTALL_PREFIX
#   macOS  — copies the Homebrew opencv into INSTALL_PREFIX
# Slow path (fallback): builds from source.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "opencv" && exit 0

# ---------------------------------------------------------------------------
# Helper: copy an installed opencv into INSTALL_PREFIX.
# Arguments: <lib-dir> <include-dir> [cmake-config-dir]
# ---------------------------------------------------------------------------
install_from_prefix() {
    local libdir="$1" incdir="$2" cmakedir="${3:-}"

    mkdir -p "$INSTALL_PREFIX/lib" "$INSTALL_PREFIX/include"

    # Copy all libopencv_* shared libs — dereference symlinks for real files.
    find "$libdir" -maxdepth 1 \
        \( -name 'libopencv_*.so*' -o -name 'libopencv_*.dylib' -o -name 'libopencv_*.*.dylib' \) \
        | while read -r f; do
            cp -LRf "$f" "$INSTALL_PREFIX/lib/" 2>/dev/null || cp -Rf "$f" "$INSTALL_PREFIX/lib/"
        done

    # Headers — keep the opencv4/ subdir that #include <opencv2/…> expects.
    if [[ -d "$incdir/opencv4" ]]; then
        cp -rn "$incdir/opencv4" "$INSTALL_PREFIX/include/" 2>/dev/null || true
    fi

    # CMake config files — needed for find_package(OpenCV) in downstream builds.
    if [[ -n "$cmakedir" && -d "$cmakedir" ]]; then
        mkdir -p "$INSTALL_PREFIX/lib/cmake"
        cp -r "$cmakedir" "$INSTALL_PREFIX/lib/cmake/"
    fi
}

# ---------------------------------------------------------------------------
# Fast path: Linux with a system-installed libopencv-dev
# ---------------------------------------------------------------------------
if [[ "$OS" == "Linux" ]]; then
    LIBOPENCV="$(ldconfig -p 2>/dev/null | awk '/libopencv_core\.so /{print $NF}' | head -1)"
    if [[ -n "$LIBOPENCV" ]]; then
        log "Using system OpenCV."
        LIBDIR="$(dirname "$LIBOPENCV")"

        CMAKE_DIR=""
        for d in "$LIBDIR/cmake/opencv4" /usr/lib/cmake/opencv4; do
            [[ -d "$d" ]] && { CMAKE_DIR="$d"; break; }
        done

        install_from_prefix "$LIBDIR" /usr/include "$CMAKE_DIR"
        mark_built "opencv"
        log "OpenCV installed from system packages."
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Fast path: macOS with Homebrew opencv
# ---------------------------------------------------------------------------
if [[ "$OS" == "Darwin" ]] && command -v brew &>/dev/null; then
    if ! brew list opencv &>/dev/null; then
        log "Installing OpenCV via Homebrew..."
        brew install opencv
    fi
    BREW_PREFIX="$(brew --prefix opencv)"

    CMAKE_DIR=""
    [[ -d "$BREW_PREFIX/lib/cmake/opencv4" ]] && CMAKE_DIR="$BREW_PREFIX/lib/cmake/opencv4"

    install_from_prefix "$BREW_PREFIX/lib" "$BREW_PREFIX/include" "$CMAKE_DIR"
    mark_built "opencv"
    log "OpenCV installed from Homebrew."
    exit 0
fi

# ---------------------------------------------------------------------------
# Slow path: build from source
# ---------------------------------------------------------------------------
log "No pre-built OpenCV found. Building from source (this will take a while)..."

SRCDIR="$WORK_DIR/opencv"
URL="https://github.com/opencv/opencv/archive/refs/tags/$OPENCV_VERSION.tar.gz"
TARBALL="$WORK_DIR/opencv-$OPENCV_VERSION.tar.gz"
download_tarball "$URL" "$TARBALL" "$SRCDIR"

cd "$SRCDIR"
cmake -B build \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$INSTALL_PREFIX" \
    -DBUILD_LIST="core,imgproc,calib3d,features2d,flann" \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTS=OFF \
    -DBUILD_PERF_TESTS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_DOCS=OFF \
    -DBUILD_opencv_apps=OFF \
    -DWITH_CUDA=OFF \
    -DWITH_OPENCL=OFF \
    -DWITH_OPENMP=OFF \
    -DWITH_FFMPEG=OFF \
    -DWITH_GSTREAMER=OFF \
    -DWITH_GTK=OFF \
    -DWITH_QT=OFF \
    -DWITH_V4L=OFF \
    -DWITH_EIGEN=OFF \
    -DOPENCV_GENERATE_PKGCONFIG=OFF \
    -DBUILD_opencv_python2=OFF \
    -DBUILD_opencv_python3=OFF

cmake --build build -j"$NPROC"
cmake --install build

mark_built "opencv"
log "OpenCV $OPENCV_VERSION installed."
