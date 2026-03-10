#!/usr/bin/env bash
# Assemble a relocatable tarball from the install prefix.
#
# What goes in:
#   bin/   - mrcal-*, mrgingham, vnlog CLI tools
#   lib/   - libmrcal, libmrgingham, libdogleg, libvnlog +
#            all transitive .so/.dylib deps from our prefix
#   include/mrcal/  - public headers
#   lib/cmake/mrcal/ - CMake package config
#
# On Linux:  uses patchelf to rewrite RPATH → $ORIGIN/../lib
# On macOS:  uses install_name_tool to rewrite paths → @loader_path/../lib
set -euo pipefail
source "$(dirname "$0")/common.sh"

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
# mrcal CLI tools (mrcal-calibrate-cameras, mrcal-show-*, etc.)
find "$INSTALL_PREFIX/bin" -maxdepth 1 -name 'mrcal-*' -type f \
    -exec cp -a {} "$STAGE_DIR/bin/" \;
# mrgingham tools
for bin in mrgingham mrgingham-observe-pixel-uncertainty mrgingham-rotate-corners; do
    [[ -f "$INSTALL_PREFIX/bin/$bin" ]] && cp -a "$INSTALL_PREFIX/bin/$bin" "$STAGE_DIR/bin/"
done
# vnlog tools
find "$INSTALL_PREFIX/bin" -maxdepth 1 -name 'vnl-*' -type f \
    -exec cp -a {} "$STAGE_DIR/bin/" \;

# ---------------------------------------------------------------------------
# 2. Collect our non-system shared libraries
# ---------------------------------------------------------------------------
log "Collecting libraries..."
# The set of libs we own (not system libs like libc, libpthread, libm, libz …)
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
    # Match .so* or .dylib on macOS
    find "${search_dirs[@]}" \
        -maxdepth 1 \( -name "${name}.so*" -o -name "${name}.dylib" -o -name "${name}.*.dylib" \) \
        -not -type d \
        2>/dev/null | while read -r f; do
            cp -a "$f" "$STAGE_DIR/lib/" 2>/dev/null || true
        done || true
}

for lib in "${OWNED_LIBS[@]}"; do
    copy_lib "$lib"
done

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
# 4. Fix up RPATHs so the package is relocatable
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
    # Replace any reference to our build-time prefix with @loader_path/../lib
    otool -L "$file" 2>/dev/null | awk 'NR>1 {print $1}' | while read -r dep; do
        if [[ "$dep" == "$INSTALL_PREFIX"* ]]; then
            local newname="@loader_path/../lib/$(basename "$dep")"
            install_name_tool -change "$dep" "$newname" "$file" 2>/dev/null || true
        fi
    done
    # For shared libs also fix their own install_name (id)
    if [[ "$file" == *.dylib ]]; then
        install_name_tool -id "@rpath/$(basename "$file")" "$file" 2>/dev/null || true
    fi
}

find "$STAGE_DIR/bin" "$STAGE_DIR/lib" -maxdepth 1 -type f | while read -r f; do
    if [[ "$OS" == "Linux" ]]; then
        fix_rpath_linux "$f"
    elif [[ "$OS" == "Darwin" ]]; then
        fix_rpath_macos "$f"
    fi
done

# ---------------------------------------------------------------------------
# 5. Write CMake package config
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
# 6. Create tarball
# ---------------------------------------------------------------------------
TARBALL="$OUT_DIR/${PKG_NAME}.tar.gz"
log "Creating $TARBALL ..."
tar -C "$WORK_DIR/stage" -czf "$TARBALL" "$PKG_NAME"

log "Package ready: $TARBALL"
echo "$TARBALL"
