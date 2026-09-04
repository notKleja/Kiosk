#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
swiftc -O \
	-target arm64-apple-macos26.0 \
	-o build/kiosk \
	Sources/PlayStore.swift Sources/IconRenderer.swift cli/main.swift

echo "built build/kiosk"
