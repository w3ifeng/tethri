#!/bin/zsh
# Isolated UI fixture: mock replies, separate settings, no app/Chrome monitoring.
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build --disable-sandbox --cache-path "$PWD/.build/cache"
preview="$PWD/build/Tethri Preview.app"
mkdir -p "$preview/Contents/MacOS" "$preview/Contents/Resources"
cp .build/debug/FocusCompanion "$preview/Contents/MacOS/.FocusCompanion.next"
mv -f "$preview/Contents/MacOS/.FocusCompanion.next" "$preview/Contents/MacOS/FocusCompanion"
cp Sources/FocusCompanion/Resources/* "$preview/Contents/Resources/"
cp scripts/Info.plist "$preview/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.focuscompanion.preview' "$preview/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Tethri Preview' "$preview/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Tethri Preview' "$preview/Contents/Info.plist"
python3 scripts/configure-updates.py "$preview" --disable
zsh scripts/embed-sparkle.sh "$preview"
codesign --force --sign - "$preview"
print -r -- "$preview"
