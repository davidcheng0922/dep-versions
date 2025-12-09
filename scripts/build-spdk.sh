#!/bin/bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Illegal number of parameters"
    exit 1
fi

MAIN_DIR=$(dirname $(dirname $(realpath $0)))

REPO_OVERRIDE="$1"
COMMIT_ID_OVERRIDE="$2"
ARCH="$3"
SRC_DIR="/usr/src/spdk"

# Fetch repo and commit ID from versions.json, with optional overrides
SPDK_REPO=$(jq -r '.["spdk"].repo' ${MAIN_DIR}/versions.json)
SPDK_COMMIT_ID=$(jq -r '.["spdk"].commit' ${MAIN_DIR}/versions.json)

# Apply overrides if provided
if [[ -n "$REPO_OVERRIDE" ]]; then
    SPDK_REPO="$REPO_OVERRIDE"
fi

if [[ -n "$COMMIT_ID_OVERRIDE" ]]; then
    SPDK_COMMIT_ID="$COMMIT_ID_OVERRIDE"
fi

# Clone the repository
git clone --recursive "$SPDK_REPO" "$SRC_DIR"

# Checkout the specific commit
cd "$SRC_DIR"
git checkout "$SPDK_COMMIT_ID"
git submodule update --init

zypper refresh
sed -i '/python3-pyelftools/d' ./scripts/pkgdep/sles.sh
sed -i 's/python3-/python311-/g' ./scripts/pkgdep/sles.sh

# Install dependencies
./scripts/pkgdep.sh --uring
pip3 install -r ./scripts/pkgdep/requirements.txt

# Build and install based on architecture
case "$ARCH" in
    amd64)
        ./configure --target-arch=nehalem --disable-tests --disable-unit-tests --disable-examples --with-ublk --enable-debug
        make -j"$(nproc)"
        make install
        ;;
    arm64)
        CFLAGS="-march=armv8-a" CC="gcc-13" ./configure --target-arch=armv8-a --disable-tests --disable-unit-tests --disable-examples --with-ublk --enable-debug
        DPDKBUILD_FLAGS="-Dplatform=generic" make -j"$(nproc)"
        make install
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac
