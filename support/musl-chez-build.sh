#!/bin/bash
# musl-chez-build.sh — Build Chez Scheme with musl libc (system install)
#
# Uses Chez Scheme's native --static flag (v10.4.0+) which:
#   - Adds -static to LDFLAGS
#   - Disables dynamic loading (no dlopen)
#   - Disables curses, x11, iconv
#   - Embeds boot files via static_boot_init()
#   - Provides main.o for downstream static builds
#
# Usage:
#   sudo ./musl-chez-build.sh [chez-source-dir] [install-prefix]
#
# Examples:
#   sudo ./musl-chez-build.sh ~/mine/ChezScheme /opt/chez-musl
#   sudo ./musl-chez-build.sh  # uses defaults
set -euo pipefail

CHEZ_DIR="${1:-$HOME/mine/ChezScheme}"
INSTALL_PREFIX="${2:-/opt/chez-musl}"

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

# Install
echo "==> Installing to $INSTALL_PREFIX..."
make install

# Summary
echo ""
echo "==================================="
echo "musl Chez Scheme installed to $INSTALL_PREFIX"
echo "==================================="
echo ""
echo "Set for jerboa:"
echo "  export JERBOA_MUSL_CHEZ_PREFIX=$INSTALL_PREFIX"
echo ""
echo "Or build directly:"
echo "  scheme --libdirs lib --script your-build.ss"
