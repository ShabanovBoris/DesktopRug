#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_cache="$task_root/build/test-cache"
mkdir -p "$task_cache"
cd "$task_root"
export CLANG_MODULE_CACHE_PATH="$task_cache/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_cache/modules"
swift test -c release --scratch-path "$task_cache/products" --cache-path "$task_cache/packages" --config-path "$task_cache/config" --security-path "$task_cache/security" --disable-sandbox
