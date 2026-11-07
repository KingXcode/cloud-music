#!/usr/bin/env bash
set -euo pipefail
: "${RUNNER_TEMP:?Run this setup on a GitHub Actions runner}"
FLUTTER_ROOT="$RUNNER_TEMP/cloud-music-flutter"
if [[ ! -d "$FLUTTER_ROOT/.git" ]]; then
  git clone --depth 1 --branch 3.47.5 https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
fi
printf '%s\n' "$FLUTTER_ROOT/bin" >> "$GITHUB_PATH"
export BOT=true FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true
"$FLUTTER_ROOT/bin/flutter" --version
