#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

BIN="$WORKDIR/tests"

swiftc -target arm64-apple-macos26.0 \
    -o "$BIN" \
    ../Sources/PlayStore.swift Tests.swift

set +e
"$BIN"
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
    echo "run.sh: all tests passed"
else
    echo "run.sh: tests failed"
fi

exit "$STATUS"
