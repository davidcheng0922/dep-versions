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

# --- START SLES Dependency Fixes (Robust Zypper and Python package resolution) ---

# Retry zypper refresh to ensure repository metadata is current and stable
for i in {1..5}; do
    if zypper refresh; then
        echo "zypper refresh succeeded on attempt $i."
        break
    else
        echo "zypper refresh failed on attempt $i. Retrying in 5 seconds..." >&2
        sleep 5
    fi
done

# Modify SPDK's SLES dependency script to resolve Python package name conflicts/issues
# 1. Remove 'python3-pyelftools' as it frequently causes "Package not found" errors.
sed -i '/python3-pyelftools/d' ./scripts/pkgdep/sles.sh

# 2. Change other 'python3-' prefixes to 'python311-' for compatibility with bci-base:15.7
sed -i 's/python3-/python311-/g' ./scripts/pkgdep/sles.sh

# --- END SLES Dependency Fixes ---

# Install dependencies using the modified SPDK script and pip
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