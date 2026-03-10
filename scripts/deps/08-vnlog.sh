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

# vnlog's GNUmakefile has 'install: doc' where doc generates man pages via the
# pattern rule 'man1/%.1: % | man1/'.  GNU make rejects the pattern rule if the
# order-only prerequisite directory doesn't exist and has no creation rule.
# Pre-create the directories so pod2man can run (pages are generated but not
# installed since DIST_MAN= is passed to make install).
mkdir -p "$SRCDIR/man1" "$SRCDIR/man3"

export CFLAGS="-I$INSTALL_PREFIX/include"
export LDFLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib"

make -j"$NPROC" PREFIX="$INSTALL_PREFIX"

# Skip Python and Perl module distribution; we only want the C lib + CLI tools.
make install "${MRBUILD_INSTALL_ARGS[@]}" DIST_PY3_MODULES= DIST_PY2_MODULES= DIST_PERL_MODULES=

mark_built "vnlog"
log "vnlog installed."
