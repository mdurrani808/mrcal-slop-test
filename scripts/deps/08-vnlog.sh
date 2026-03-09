#!/usr/bin/env bash
# Build vnlog (log tooling used by mrcal CLI tools).
set -euo pipefail
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../versions.sh"

already_built "vnlog" && exit 0

SRCDIR="$WORK_DIR/vnlog"
git_clone_or_update "$SRCDIR" "https://github.com/dkogan/vnlog.git" "$VNLOG_REF"

cd "$SRCDIR"
ln -sfn "$MRBUILD_MK" "$SRCDIR/mrbuild"

export CFLAGS="-I$INSTALL_PREFIX/include"
export LDFLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib"

make -j"$NPROC" PREFIX="$INSTALL_PREFIX"

# Skip Python and Perl module distribution; we only want the C lib + CLI tools.
make install PREFIX="$INSTALL_PREFIX" DESTDIR=/ DIST_PY3_MODULES= DIST_PY2_MODULES= DIST_PERL_MODULES=

mark_built "vnlog"
log "vnlog installed."
