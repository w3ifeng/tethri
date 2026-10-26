#!/bin/zsh
# Build release assets locally. No GitHub credentials or publishing are needed here.
set -eu
cd "${0:A:h}/.."
repo="${1:?Usage: APP_VERSION=0.2.0 BUILD_NUMBER=2 scripts/prepare-github-release.sh owner/tethri}"
if [[ ! "$repo" =~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ]]; then print -u2 'Expected owner/repository'; exit 1; fi
: "${APP_VERSION:?Set APP_VERSION, for example 0.2.0}"
: "${BUILD_NUMBER:?Set BUILD_NUMBER to a new, increasing integer}"
tag="v${APP_VERSION}-${BUILD_NUMBER}"
export UPDATE_FEED_URL="https://github.com/$repo/releases/latest/download/appcast.xml"
export UNIVERSAL=1
export CONFIGURATION=release
if [[ -n "${DEVELOPER_ID:-}" && -z "${NOTARY_PROFILE:-}" ]]; then
  print -u2 'Set NOTARY_PROFILE when preparing a Developer ID signed public release.'
  exit 1
fi
zsh scripts/build-app.sh
if [[ -n "${DEVELOPER_ID:-}" ]]; then zsh scripts/notarize.sh; fi
python3 scripts/prepare-update.py --download-url-prefix "https://github.com/$repo/releases/download/$tag/"
print -r -- "Assets are ready in build/updates. Create a GitHub release with tag $tag and upload Tethri-${APP_VERSION}-${BUILD_NUMBER}.zip and appcast.xml."
print -r -- 'Publish it as a normal release and mark it Latest. Drafts and prereleases do not serve the latest update feed.'
