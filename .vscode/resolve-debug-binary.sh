#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app=$(xcodebuild -scheme "claude spinner" -configuration Debug -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')
if [ -z "$app" ] || [ "$app" = "/" ]; then
    echo "error: could not resolve BUILT_PRODUCTS_DIR / FULL_PRODUCT_NAME" >&2
    exit 1
fi

binary="$app/Contents/MacOS/claude spinner"
ln -sfn "$binary" "$root/.vscode/debug-binary"
echo "debug binary -> $binary"
