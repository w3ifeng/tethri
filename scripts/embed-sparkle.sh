#!/bin/zsh
# Embed the universal Sparkle framework and sign nested code before signing the host app.
set -eu
cd "${0:A:h}/.."
app="${1:?Pass the app bundle path}"
framework="$app/Contents/Frameworks/Sparkle.framework"
source_framework="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$app/Contents/MacOS" && -d "$source_framework" ]] || { print -u2 "Build the app with SwiftPM before embedding Sparkle."; exit 1; }
mkdir -p "$app/Contents/Frameworks"
rm -rf "$framework"
ditto "$source_framework" "$framework"
mkdir -p "$app/Contents/Resources"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$app/Contents/Resources/SPARKLE-LICENSE.txt"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  for component in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    extra=()
    if [[ "$component" == XPCServices/Downloader.xpc ]]; then extra=(--preserve-metadata=entitlements); fi
    codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp "${extra[@]}" "$framework/Versions/B/$component"
  done
  codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp "$framework"
fi
