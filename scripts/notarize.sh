#!/bin/zsh
set -eu
cd "${0:A:h}/.."
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool Keychain profile}"
app="$PWD/build/Tethri.app"
codesign --verify --deep --strict "$app"
mkdir -p build
ditto -c -k --keepParent "$app" build/Tethri.zip
xcrun notarytool submit build/Tethri.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
ditto -c -k --keepParent "$app" build/Tethri.zip
