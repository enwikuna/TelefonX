#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p .build/module-cache .build/cache
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
COMMAND="${1:-build}"
if [[ $# -gt 0 ]]; then shift; fi
exec swift "$COMMAND" --arch arm64 --disable-sandbox --cache-path "$ROOT_DIR/.build/cache" "$@"
