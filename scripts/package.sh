#!/usr/bin/env bash
# Assemble a relocatable tarball from the install prefix.
#
# What goes in:
#   bin/      - mrcal-*, mrgingham, vnlog CLI tools
#   lib/      - libmrcal, libmrgingham, libdogleg, libvnlog +
#               all transitive .so/.dylib deps from our prefix
#   include/  - mrcal and mrgingham public headers
#   licenses/ - LICENSE files for all bundled libraries (Apache 2.0 compliance)
#   lib/cmake/mrcal/ - CMake package config
#
# On Linux:  uses patchelf to rewrite RPATH → $ORIGIN/../lib
# On macOS:  uses install_name_tool to rewrite paths → @loader_path/../lib
set -euo pipefail
source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/versions.sh"

# OS comes from common.sh ("Linux" or "Darwin"); use lowercase only for the filename.
OS_LOWER="$(echo "$OS" | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
MRCAL_VERSION="${MRCAL_VERSION:-$(git -C "$WORK_DIR/mrcal" describe --tags --always 2>/dev/null || echo "dev")}"
PKG_NAME="mrcal-${MRCAL_VERSION}-${OS_LOWER}-${ARCH}"
STAGE_DIR="$WORK_DIR/stage/$PKG_NAME"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/artifacts}"

# Always start from a clean stage dir so reruns don't include stale files.
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"/{bin,lib,include} "$OUT_DIR"

# ---------------------------------------------------------------------------
# 1. Collect binaries
# ---------------------------------------------------------------------------
log "Collecting binaries..."
find "$INSTALL_PREFIX/bin" -maxdepth 1 -name 'mrcal-*' -type f \
    -exec cp -a {} "$STAGE_DIR/bin/" \;
for bin in mrgingham mrgingham-observe-pixel-uncertainty mrgingham-rotate-corners; do
    [[ -f "$INSTALL_PREFIX/bin/$bin" ]] && cp -a "$INSTALL_PREFIX/bin/$bin" "$STAGE_DIR/bin/"
done
find "$INSTALL_PREFIX/bin" -maxdepth 1 -name 'vnl-*' -type f \
    -exec cp -a {} "$STAGE_DIR/bin/" \;

# ---------------------------------------------------------------------------
# 2. Collect our non-system shared libraries
# ---------------------------------------------------------------------------
log "Collecting libraries..."
# Libs we bundle — everything except system libs like libc/libpthread/libm.
OWNED_LIBS=(
    libmrcal
    libmrgingham
    libdogleg
    libvnlog
    libcholmod
    libopenblas
    libsuitesparseconfig
    libamd
    libcamd
    libcolamd
    libccolamd
    libopencv_core
    libopencv_imgproc
    libopencv_calib3d
    libopencv_features2d
    libopencv_flann
)

copy_lib() {
    local name="$1"
    local search_dirs=()
    [[ -d "$INSTALL_PREFIX/lib" ]]   && search_dirs+=("$INSTALL_PREFIX/lib")
    [[ -d "$INSTALL_PREFIX/lib64" ]] && search_dirs+=("$INSTALL_PREFIX/lib64")
    [[ ${#search_dirs[@]} -eq 0 ]] && return 0
    # Match both libfoo.*.dylib and libfoo.dylib.* — macOS uses both conventions.
    find "${search_dirs[@]}" \
        -maxdepth 1 \( -name "${name}.so*" -o -name "${name}.dylib" -o -name "${name}.*.dylib" -o -name "${name}.dylib.*" \) \
        -not -type d \
        2>/dev/null | while read -r f; do
            cp -a "$f" "$STAGE_DIR/lib/" 2>/dev/null || true
        done || true
}

for lib in "${OWNED_LIBS[@]}"; do
    copy_lib "$lib"
done

# Some deps come from apt/brew rather than our build prefix, so copy_lib won't
# find them. Bundle them explicitly to keep the tarball self-contained.
if is_linux; then
    SYSTEM_LIB_SEARCH_DIRS=(
        /usr/lib
        /usr/lib/x86_64-linux-gnu
        /usr/lib/aarch64-linux-gnu
        /usr/lib64
    )
    for syslib in libstb libgfortran libquadmath; do
        for dir in "${SYSTEM_LIB_SEARCH_DIRS[@]}"; do
            [[ -d "$dir" ]] || continue
            find "$dir" -maxdepth 1 -name "${syslib}.so*" -not -type d \
                2>/dev/null | while read -r f; do
                    cp -L "$f" "$STAGE_DIR/lib/$(basename "$f")" 2>/dev/null || true
                done
        done
    done

    # liblapack.so.3 is managed by update-alternatives with absolute symlinks that
    # break off-system. Point it at our bundled OpenBLAS instead.
    if [[ ! -e "$STAGE_DIR/lib/liblapack.so.3" ]]; then
        for ob in libopenblas.so libopenblas.so.0; do
            if [[ -e "$STAGE_DIR/lib/$ob" ]]; then
                ln -sf "$ob" "$STAGE_DIR/lib/liblapack.so.3"
                break
            fi
        done
    fi
fi

# libomp is a Homebrew dep of SuiteSparse, not in $INSTALL_PREFIX.
if is_macos; then
    BREW_LIBOMP_DIRS=(
        /opt/homebrew/opt/libomp/lib   # Apple Silicon
        /usr/local/opt/libomp/lib      # Intel Mac
    )
    for dir in "${BREW_LIBOMP_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        find "$dir" -maxdepth 1 \( -name "libomp.dylib" -o -name "libomp.*.dylib" \) \
            -not -type d 2>/dev/null | while read -r f; do
                cp -a "$f" "$STAGE_DIR/lib/" 2>/dev/null || true
            done
    done
fi

# ---------------------------------------------------------------------------
# 3. Collect headers (mrcal public API only)
# ---------------------------------------------------------------------------
log "Collecting headers..."
if [[ -d "$INSTALL_PREFIX/include/mrcal" ]]; then
    cp -a "$INSTALL_PREFIX/include/mrcal" "$STAGE_DIR/include/"
fi
# mrgingham headers (needed if consuming mrgingham directly from C++)
if [[ -d "$INSTALL_PREFIX/include/mrgingham" ]]; then
    cp -a "$INSTALL_PREFIX/include/mrgingham" "$STAGE_DIR/include/"
fi

# ---------------------------------------------------------------------------
# 4. Collect licenses (required by Apache 2.0, BSD 3-Clause, and LGPL)
# ---------------------------------------------------------------------------
log "Collecting licenses..."
LICENSES_DIR="$STAGE_DIR/licenses"
mkdir -p "$LICENSES_DIR"

# Copies any standard license files from a source dir into $LICENSES_DIR.
copy_license_from_dir() {
    local prefix="$1" srcdir="$2"
    local found=0
    [[ -d "$srcdir" ]] || return 1
    for f in LICENSE LICENSE.txt COPYING COPYING.txt NOTICE NOTICE.txt; do
        if [[ -f "$srcdir/$f" ]]; then
            cp "$srcdir/$f" "$LICENSES_DIR/${prefix}-${f}"
            found=1
        fi
    done
    return $((1 - found))
}

# Fetches a license file from a URL if not already present.
fetch_license() {
    local dest="$LICENSES_DIR/$1" url="$2"
    [[ -f "$dest" ]] && return 0
    log "Fetching license: $1"
    curl -fsSL "$url" -o "$dest" 2>/dev/null \
        || log "WARNING: could not fetch license for $1 from $url"
}

copy_license_from_dir "mrcal" "$WORK_DIR/mrcal"
copy_license_from_dir "libdogleg" "$WORK_DIR/libdogleg"

# mrgingham has no top-level license file in its repo — fall back to the canonical text.
copy_license_from_dir "mrgingham" "$WORK_DIR/mrgingham" \
    || fetch_license "mrgingham-LICENSE-LGPL-2.1.txt" \
        "https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt"

copy_license_from_dir "vnlog" "$WORK_DIR/vnlog" || true

# Tarball-extracted projects may not be in WORK_DIR if the fast path was used — fetch from GitHub.
copy_license_from_dir "openblas" "$WORK_DIR/OpenBLAS" \
    || fetch_license "openblas-LICENSE" \
        "https://raw.githubusercontent.com/OpenMathLib/OpenBLAS/v${OPENBLAS_VERSION}/LICENSE"

copy_license_from_dir "opencv" "$WORK_DIR/opencv" \
    || fetch_license "opencv-LICENSE" \
        "https://raw.githubusercontent.com/opencv/opencv/${OPENCV_VERSION}/LICENSE"

# SuiteSparse has per-component licenses (Apache 2.0, BSD 3-Clause, LGPL 2.1+).
if [[ -d "$WORK_DIR/SuiteSparse" ]]; then
    for comp in SuiteSparse_config AMD CAMD COLAMD CCOLAMD CHOLMOD; do
        for f in License.txt LICENSE.txt Doc/License.txt Doc/LICENSE.txt; do
            src="$WORK_DIR/SuiteSparse/$comp/$f"
            if [[ -f "$src" ]]; then
                cp "$src" "$LICENSES_DIR/suitesparse-${comp}-LICENSE.txt"
                break
            fi
        done
    done
else
    # Fast-path fallback: fetch per-component license files from GitHub.
    for comp in AMD CAMD COLAMD CCOLAMD CHOLMOD; do
        fetch_license "suitesparse-${comp}-LICENSE.txt" \
            "https://raw.githubusercontent.com/DrTimothyAldenDavis/SuiteSparse/v${SUITESPARSE_VERSION}/${comp}/Doc/License.txt"
    done
    fetch_license "suitesparse-config-LICENSE.txt" \
        "https://raw.githubusercontent.com/DrTimothyAldenDavis/SuiteSparse/v${SUITESPARSE_VERSION}/SuiteSparse_config/License.txt"
fi

# ---------------------------------------------------------------------------
# 5. Fix up RPATHs so the package is relocatable
# ---------------------------------------------------------------------------
log "Fixing RPATHs..."
fix_rpath_linux() {
    local file="$1"
    if ! command -v patchelf &>/dev/null; then
        echo "WARNING: patchelf not found. Skipping RPATH fix for $file." >&2
        return
    fi
    patchelf --set-rpath '$ORIGIN/../lib' "$file" 2>/dev/null || true
}

fix_rpath_macos() {
    local file="$1"
    # Rewrite deps that came from our prefix or that we bundled (e.g. Homebrew libomp).
    otool -L "$file" 2>/dev/null | awk 'NR>1 {print $1}' | while read -r dep; do
        local base
        base="$(basename "$dep")"
        if [[ "$dep" == "$INSTALL_PREFIX"* ]] || [[ -f "$STAGE_DIR/lib/$base" ]]; then
            install_name_tool -change "$dep" "@loader_path/../lib/$base" "$file" 2>/dev/null || true
        fi
    done
    if [[ "$file" == *.dylib ]]; then
        install_name_tool -id "@rpath/$(basename "$file")" "$file" 2>/dev/null || true
    fi
}

find "$STAGE_DIR/bin" "$STAGE_DIR/lib" -maxdepth 1 -type f | while read -r f; do
    if is_linux; then
        fix_rpath_linux "$f"
    elif is_macos; then
        fix_rpath_macos "$f"
    fi
done

# ---------------------------------------------------------------------------
# 6. Write CMake package config
# ---------------------------------------------------------------------------
log "Writing CMake config..."
CMAKE_DIR="$STAGE_DIR/lib/cmake/mrcal"
mkdir -p "$CMAKE_DIR"

cat > "$CMAKE_DIR/mrcal-config.cmake" <<'EOF'
# mrcal CMake package config.
# Generated by mrcal-binaries packaging script.
# Usage:
#   list(APPEND CMAKE_PREFIX_PATH "/path/to/mrcal")
#   find_package(mrcal REQUIRED)
#   target_link_libraries(my_target PRIVATE mrcal::mrcal)

cmake_minimum_required(VERSION 3.14)

get_filename_component(_mrcal_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

if(NOT TARGET mrcal::mrcal)
    add_library(mrcal::mrcal SHARED IMPORTED)

    # Detect shared lib extension
    if(APPLE)
        set(_mrcal_libname "libmrcal.dylib")
    else()
        # Find the versioned .so file
        file(GLOB _mrcal_so "${_mrcal_root}/lib/libmrcal.so*")
        list(FILTER _mrcal_so EXCLUDE REGEX ".*\\.so\\.[0-9]+\\.[0-9]+")
        if(_mrcal_so)
            list(GET _mrcal_so 0 _mrcal_libname)
            get_filename_component(_mrcal_libname "${_mrcal_libname}" NAME)
        else()
            set(_mrcal_libname "libmrcal.so")
        endif()
    endif()

    set_target_properties(mrcal::mrcal PROPERTIES
        IMPORTED_LOCATION             "${_mrcal_root}/lib/${_mrcal_libname}"
        INTERFACE_INCLUDE_DIRECTORIES "${_mrcal_root}/include"
    )
endif()

# mrgingham (optional — only if headers shipped)
if(EXISTS "${_mrcal_root}/include/mrgingham" AND NOT TARGET mrcal::mrgingham)
    add_library(mrcal::mrgingham SHARED IMPORTED)
    if(APPLE)
        set(_mrg_libname "libmrgingham.dylib")
    else()
        set(_mrg_libname "libmrgingham.so")
    endif()
    set_target_properties(mrcal::mrgingham PROPERTIES
        IMPORTED_LOCATION             "${_mrcal_root}/lib/${_mrg_libname}"
        INTERFACE_INCLUDE_DIRECTORIES "${_mrcal_root}/include"
    )
endif()

set(mrcal_FOUND TRUE)
set(MRCAL_INCLUDE_DIRS "${_mrcal_root}/include")
set(MRCAL_LIBRARIES    "${_mrcal_root}/lib/${_mrcal_libname}")
EOF

# Version file
MRCAL_VER_MAJOR="$(echo "$MRCAL_VERSION" | sed 's/^[^0-9]*\([0-9]*\).*/\1/' || echo 0)"
cat > "$CMAKE_DIR/mrcal-config-version.cmake" <<EOF
set(PACKAGE_VERSION "$MRCAL_VERSION")
set(PACKAGE_VERSION_MAJOR "$MRCAL_VER_MAJOR")
# Accept any version with the same major.
if(PACKAGE_FIND_VERSION_MAJOR EQUAL PACKAGE_VERSION_MAJOR)
    set(PACKAGE_VERSION_COMPATIBLE TRUE)
    if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)
        set(PACKAGE_VERSION_EXACT TRUE)
    endif()
endif()
EOF

# ---------------------------------------------------------------------------
# 7. Create tarball
# ---------------------------------------------------------------------------
TARBALL="$OUT_DIR/${PKG_NAME}.tar.gz"
log "Creating $TARBALL ..."
tar -C "$WORK_DIR/stage" -czf "$TARBALL" "$PKG_NAME"

log "Package ready: $TARBALL"
echo "$TARBALL"
