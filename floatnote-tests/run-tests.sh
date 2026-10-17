#!/bin/bash
# Runs the marker unit tests against the MarkerLogic code inside ../FloatNote.swift.
set -euo pipefail
cd "$(dirname "$0")"
TMP="$(mktemp -d)"
awk '/^\/\/ BEGIN MarkerLogic/{on=1} on{print} /^\/\/ END MarkerLogic/{on=0}' ../FloatNote.swift > "$TMP/MarkerLogic.swift"
{ echo "import Cocoa"; cat "$TMP/MarkerLogic.swift"; } > "$TMP/Logic.swift"
swiftc -O "$TMP/Logic.swift" main.swift -o "$TMP/tests" 2>&1 | grep -v "^$" || true
"$TMP/tests"
