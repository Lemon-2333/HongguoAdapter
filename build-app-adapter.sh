#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

ipad_test="${APP_ADAPTER_IPAD_TEST:-0}"
default_out="dist/AppAdapter-v15-hud.dylib"
if [ "$ipad_test" = "1" ]; then
  default_out="dist/AppAdapter-v36-adaptive.dylib"
fi
out="${APP_ADAPTER_OUT:-$default_out}"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
module_cache="$(mktemp -d "${TMPDIR:-/tmp}/app-adapter-clang.XXXXXX")"
trap 'rm -rf "$module_cache"' EXIT
xcrun --sdk iphoneos clang \
  -arch arm64 -dynamiclib -fobjc-arc -fmodules -fmodules-cache-path="$module_cache" \
  -miphoneos-version-min=15.0 -isysroot "$sdk" \
  -DAPP_ADAPTER_IPAD_TEST="$ipad_test" \
  -framework UIKit -framework Foundation -framework QuartzCore -framework Metal \
  -install_name "@rpath/${out##*/}" AppAdapter.m -o "$out"
codesign -f -s - "$out"
(
  cd "$(dirname "$out")"
  zip -q -j "$(basename "${out%.dylib}.zip")" "$(basename "$out")"
)
