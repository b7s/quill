#!/usr/bin/env bash
# Build and install the quill-inject native helper.
# Requires: cmake, a C++17 compiler, and Linux kernel headers (linux/uinput.h).
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BUILD_DIR="${BUILD_DIR:-build}"

cmake -S . -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX"
cmake --build "$BUILD_DIR" -j"$(nproc 2>/dev/null || echo 4)"
cmake --install "$BUILD_DIR"

echo
echo "Installed: $PREFIX/bin/quill-inject"
case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) echo "NOTE: $PREFIX/bin is not on your PATH. Add it, or the keyboard will show an error." ;;
esac
