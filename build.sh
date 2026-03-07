#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$SCRIPT_DIR/bin"

echo "Compiling window-tool..."
swiftc -O \
  -o "$SCRIPT_DIR/bin/window-tool" \
  "$SCRIPT_DIR/src/window-tool.swift" \
  -framework Cocoa

echo "Built: $SCRIPT_DIR/bin/window-tool"
