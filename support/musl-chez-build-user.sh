#!/bin/bash
# musl-chez-build-user.sh — Build Chez Scheme with musl libc (user install)
#
# Uses Chez Scheme's native --static flag (v10.4.0+).
# Installs to ~/chez-musl by default (no sudo needed).
#
# Usage:
#   ./musl-chez-build-user.sh [chez-source-dir] [install-prefix]
#
# Examples:
#   ./musl-chez-build-user.sh ~/mine/ChezScheme ~/chez-musl
#   ./musl-chez-build-user.sh  # uses defaults
set -euo pipefail

CHEZ_DIR="${1:-$HOME/mine/ChezScheme}"
INSTALL_PREFIX="${2:-$HOME/chez-musl}"

# Check for musl-gcc
if ! command -v musl-gcc &>/dev/null; then
	echo "ERROR: musl-gcc not found. Install musl-tools package."
	exit 1
fi

if [ ! -d "$CHEZ_DIR" ]; then
	echo "ERROR: Chez Scheme source not found: $CHEZ_DIR"
	echo "Clone it: git clone https://github.com/cisco/ChezScheme.git $CHEZ_DIR"
	exit 1
fi

cd "$CHEZ_DIR"

echo "==================================="
echo "Building Chez Scheme with musl libc"
echo "==================================="
echo ""
echo "Source:  $CHEZ_DIR"
echo "Prefix:  $INSTALL_PREFIX"
echo ""

# Clean previous build
echo "==> Cleaning..."
make clean 2>/dev/null || true

# Configure with --static and musl-gcc
echo "==> Configuring with --static CC=musl-gcc..."
./configure --threads --static CC=musl-gcc --installprefix="$INSTALL_PREFIX"

# Build
echo "==> Building..."
make -j"$(nproc)"

# Verify binary is truly static
echo "==> Verifying..."
SCHEME_BIN="$(ls ta6le/bin/ta6le/scheme 2>/dev/null || ls */bin/*/scheme 2>/dev/null | head -1)"
if file "$SCHEME_BIN" | grep -q "statically linked"; then
	echo "OK: Binary is statically linked"
else
	echo "WARNING: Binary may not be fully static"
	file "$SCHEME_BIN"
fi

# Install (no sudo needed for user directory)
echo "==> Installing to $INSTALL_PREFIX..."
make install

# Summary
echo ""
echo "==================================="
echo "musl Chez Scheme installed to $INSTALL_PREFIX"
echo "==================================="
echo ""
echo "Jerboa will auto-detect ~/chez-musl."
echo "Or set explicitly:"
echo "  export JERBOA_MUSL_CHEZ_PREFIX=$INSTALL_PREFIX"
