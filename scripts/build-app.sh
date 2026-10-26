#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
configuration="${CONFIGURATION:-release}"
app="$PWD/build/Tethri.app"
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  for architecture in arm64 x86_64; do
    swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c "$configuration" --triple "$architecture-apple-macosx13.0"
  done
  arm_dir=$(swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c "$configuration" --triple arm64-apple-macosx13.0 --show-bin-path)
  intel_dir=$(swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c "$configuration" --triple x86_64-apple-macosx13.0 --show-bin-path)
  mkdir -p "$app/Contents/MacOS"
  lipo -create "$arm_dir/FocusCompanion" "$intel_dir/FocusCompanion" -output "$app/Contents/MacOS/.FocusCompanion.next"
  mv -f "$app/Contents/MacOS/.FocusCompanion.next" "$app/Contents/MacOS/FocusCompanion"
else
  swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c "$configuration"
  binary_dir=$(swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c "$configuration" --show-bin-path)
  mkdir -p "$app/Contents/MacOS"
  cp "$binary_dir/FocusCompanion" "$app/Contents/MacOS/.FocusCompanion.next"
  mv -f "$app/Contents/MacOS/.FocusCompanion.next" "$app/Contents/MacOS/FocusCompanion"
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Sources/FocusCompanion/Resources/* "$app/Contents/Resources/"
cp scripts/Info.plist "$app/Contents/Info.plist"
if [[ -n "${BACKEND_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CompanionBackendURL $BACKEND_URL" "$app/Contents/Info.plist"
fi
python3 scripts/configure-updates.py "$app"
zsh scripts/embed-sparkle.sh "$app"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --entitlements scripts/FocusCompanion.entitlements --sign "$DEVELOPER_ID" "$app"
else
  codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
print -r -- "$app"
