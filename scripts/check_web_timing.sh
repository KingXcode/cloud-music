#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
probe=test/dart2js/lyrics_timing_probe.dart
dart "$probe"
dart compile js -O2 --no-source-maps -o "$out/lyrics_timing.js" "$probe"
node "$out/lyrics_timing.js"
