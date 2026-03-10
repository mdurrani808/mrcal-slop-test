#!/usr/bin/env bash
# Top-level orchestration: builds all deps, then mrcal, then packages.
# Run this script directly on a host (or inside Docker for Linux).
#
# Environment variables you can set:
#   WORK_DIR        — scratch space for sources/builds  (default: /tmp/mrcal-build)
#   INSTALL_PREFIX  — where everything is installed     (default: <repo>/install)
#   OUT_DIR         — where the final tarball is placed (default: <repo>/artifacts)
#   NPROC           — parallel jobs                     (default: nproc)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_step() {
    local script="$1"
    [[ -f "$script" ]] || { echo "ERROR: step script not found: $script" >&2; exit 1; }
    echo ""
    echo "================================================================"
    echo " STEP: $script"
    echo "================================================================"
    bash "$script"
}

run_step "$SCRIPT_DIR/deps/01-re2c.sh"
run_step "$SCRIPT_DIR/deps/02-mrbuild.sh"
run_step "$SCRIPT_DIR/deps/03-openblas.sh"
run_step "$SCRIPT_DIR/deps/04-suitesparse.sh"
run_step "$SCRIPT_DIR/deps/05-libdogleg.sh"
run_step "$SCRIPT_DIR/deps/06-opencv.sh"
run_step "$SCRIPT_DIR/deps/07-mrgingham.sh"
run_step "$SCRIPT_DIR/deps/08-vnlog.sh"
run_step "$SCRIPT_DIR/build-mrcal.sh"
run_step "$SCRIPT_DIR/package.sh"
