# mrcal-binaries

Unofficial pre-built binaries for [mrcal](https://mrcal.secretsauce.net) — a
camera calibration and structure-from-motion library by Dima Kogan.

All dependencies (OpenBLAS, SuiteSparse/CHOLMOD, libdogleg, OpenCV, mrgingham,
vnlog) are built from source and bundled in the tarball. The only runtime
requirements are libc and libstdc++.

> **No Python support.** These builds provide the C library and CLI tools only.
> If you need Python bindings, use the [official Debian/Ubuntu packages](https://mrcal.secretsauce.net/install.html).

---

## Download

Grab a tarball from the [Releases](../../releases) page:

| File | Platform |
|------|----------|
| `mrcal-*-linux-amd64.tar.gz` | Linux x86-64, WSL2 |
| `mrcal-*-linux-arm64.tar.gz` | Linux ARM64 |
| `mrcal-*-Darwin-arm64.tar.gz` | macOS Apple Silicon |
| `mrcal-*-Darwin-x86_64.tar.gz` | macOS Intel |

Extract anywhere:

```bash
tar -xzf mrcal-*-linux-amd64.tar.gz
```

---

## Using from CMake

```cmake
# Point CMake at the extracted directory
list(APPEND CMAKE_PREFIX_PATH "/path/to/mrcal-2.5-linux-amd64")
find_package(mrcal REQUIRED)

add_executable(my_app main.c)
target_link_libraries(my_app PRIVATE mrcal::mrcal)
```

Or pass on the command line:

```bash
cmake -DCMAKE_PREFIX_PATH=/path/to/mrcal-2.5-linux-amd64 ..
```

The package exports two targets:

| Target | Description |
|--------|-------------|
| `mrcal::mrcal` | Main C library + headers |
| `mrcal::mrgingham` | Chessboard corner finder (C++ library) |

---

## Building from Source

If you want to build the binaries yourself (or modify the scripts):

### Prerequisites

**Linux (Docker):** Docker is the only requirement. The Dockerfile installs
everything else.

**macOS:** Xcode Command Line Tools + cmake + make. No Homebrew needed.

```bash
xcode-select --install
```

### Build

```bash
# Linux (produces a Docker image and copies the tarball out)
docker build -f docker/Dockerfile.linux-amd64 -t mrcal-builder .
docker create --name tmp mrcal-builder
docker cp tmp:/artifacts/. ./artifacts/
docker rm tmp

# macOS (runs natively)
WORK_DIR=/tmp/mrcal-build \
INSTALL_PREFIX=/tmp/mrcal-deps \
OUT_DIR=$PWD/artifacts \
bash scripts/build-all.sh
```

### Customisation

Edit `scripts/versions.sh` to pin different git refs or dependency versions.

Each dependency has its own numbered script in `scripts/deps/`. The order
matters (dependency order):

```
01-re2c.sh          build-time parser generator
02-mrbuild.sh       mrcal's Make framework (build-time)
03-openblas.sh      BLAS + LAPACK
04-suitesparse.sh   CHOLMOD (sparse Cholesky)
05-libdogleg.sh     dog-leg optimizer
06-opencv.sh        image processing (minimal build)
07-mrgingham.sh     chessboard corner finder
08-vnlog.sh         log tooling
```

Then `scripts/build-mrcal.sh` builds mrcal itself, and `scripts/package.sh`
assembles the relocatable tarball.

---

## Versioning

Release tags follow the pattern `v<mrcal-version>[-unofficial-N]`, e.g.
`v2.5-unofficial-1`. The mrcal git ref is set in `scripts/versions.sh`.

---

## Disclaimer

These are **unofficial** builds not affiliated with or endorsed by the mrcal
project. Please verify the [mrcal license](https://github.com/dkogan/mrcal/blob/master/LICENSE)
allows binary redistribution for your use case before using these builds
commercially.
