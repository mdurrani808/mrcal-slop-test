#!/usr/bin/env bash
# Build OpenCV (minimal: core, imgproc, calib3d only — needed by mrgingham).
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "opencv" && exit 0

SRCDIR="$WORK_DIR/opencv"
URL="https://github.com/opencv/opencv/archive/refs/tags/$OPENCV_VERSION.tar.gz"
TARBALL="$WORK_DIR/opencv-$OPENCV_VERSION.tar.gz"

log "Downloading OpenCV $OPENCV_VERSION"
curl -fsSL "$URL" -o "$TARBALL"
mkdir -p "$SRCDIR"
tar -xf "$TARBALL" -C "$SRCDIR" --strip-components=1

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
