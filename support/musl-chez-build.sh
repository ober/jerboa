#!/bin/bash
# musl-chez-build.sh — Build Chez Scheme with musl libc
set -euo pipefail

CHEZ_VERSION="${1:-v10.0.0}"
INSTALL_PREFIX="${2:-/opt/chez-musl}"
BUILD_DIR="/tmp/chez-musl-build"

# Check for musl-gcc
if ! command -v musl-gcc &>/dev/null; then
    echo "ERROR: musl-gcc not found. Install musl-tools package."
    exit 1
fi

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Clone Chez Scheme
echo "==> Cloning Chez Scheme $CHEZ_VERSION..."
git clone --depth 1 --branch "$CHEZ_VERSION" \
    https://github.com/cisco/ChezScheme.git
cd ChezScheme

# Configure
echo "==> Configuring..."
./configure --threads --installprefix="$INSTALL_PREFIX"

# Detect machine type
MACHINE=$(ls -d */ | grep -E '^[a-z]+[0-9]+[a-z]+$' | head -1 | tr -d '/')
echo "==> Machine type: $MACHINE"

# Patch makefiles to use musl-gcc
echo "==> Patching makefiles for musl..."

# Patch c/Mf-base (common C makefile)
if [ -f "c/Mf-base" ]; then
    sed -i 's/^CC = gcc$/CC = musl-gcc/' c/Mf-base
    sed -i 's/^CC = cc$/CC = musl-gcc/' c/Mf-base
fi

# Patch machine-specific makefile
if [ -f "$MACHINE/s/Mf-$MACHINE" ]; then
    sed -i 's/^CC = gcc$/CC = musl-gcc/' "$MACHINE/s/Mf-$MACHINE"
fi

# Add static flags to CFLAGS
find . -name 'Mf-*' -exec sed -i 's/CFLAGS = /CFLAGS = -static /' {} \;

# Build
echo "==> Building..."
make -j$(nproc)

# Install
echo "==> Installing to $INSTALL_PREFIX..."
sudo make install

# Verify
echo "==> Verifying musl build..."
if nm "$INSTALL_PREFIX/lib/csv"*/*/libkernel.a 2>/dev/null | grep -q "@@GLIBC"; then
    echo "WARNING: libkernel.a contains glibc references"
else
    echo "SUCCESS: libkernel.a is musl-compatible"
fi

echo "==> musl Chez Scheme installed to $INSTALL_PREFIX"
echo "    Boot files: $INSTALL_PREFIX/lib/csv*/*/*.boot"
echo "    Runtime:    $INSTALL_PREFIX/lib/csv*/*/libkernel.a"
