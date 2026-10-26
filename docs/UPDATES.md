# Tethri update releases

The updater uses [Sparkle](https://sparkle-project.org/documentation/), pinned to 2.10.0 in `Package.swift` and `Package.resolved`. It is independent of the Gemini/Neon backend.

## Configuration and behavior

- Download repository: `w3ifeng/tethri`.
- Stable feed: `https://github.com/w3ifeng/tethri/releases/latest/download/appcast.xml`.
- Public signing key: `updates.json` (safe to commit).
- Private signing key: login Keychain, Sparkle account `tethri`.
- First updater-enabled version: `0.1.1`, build `2`.

The repository/feed is not created by local build scripts. It must exist and have a published normal release. It can contain just a download README and releases; publishing app source is optional. Downloads must be publicly accessible, since no GitHub token is shipped in the app.

A configured production app starts Sparkle's scheduler on launch. Checks default to daily; users can disable them in Settings. Background checks skip active focus sessions and retry on Sparkle's next scheduled check. **Check for Updates…** allows a user-requested check when no other update operation is in progress.

Sparkle handles the release dialog, download, signature verification, installation and relaunch. Silent installation is disabled. `applicationWillTerminate` saves the existing interrupted-session checkpoint. The bundle ID stays `com.focuscompanion.mac`, preserving preferences and that checkpoint. Chat history remains in memory and clears on restart, as on a normal quit.

Preview bundles and command-line self-tests do not start update requests. A build without both settings disables the updater and says so in Settings. Partial/invalid configuration fails the build. Update links never come from the conversation service.

## Release key

After the first build, Sparkle's tools are in `.build/artifacts/sparkle/Sparkle/bin`.

```sh
# Generate or reuse a Keychain key; prints only the public key.
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account tethri

# Print the existing public key without generating another key.
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account tethri -p
```

Put the matching public key in `updates.json` before distributing the first build. Keep the same public key and stable feed URL in subsequent builds. Losing the private key can prevent installed apps from accepting updates; do not casually replace it.

Back up the private key to a secure location outside the repository with `generate_keys --account tethri -x /secure/path/key`. Treat that export as a credential: never commit it, include it in release assets, or paste it into chat. Restore on another release Mac with `generate_keys --account tethri -f /secure/path/key`. Consult [Sparkle's signing guidance](https://sparkle-project.org/documentation/) before rotating an established key.

## Prepare a GitHub release

After distributing `0.1.1` build `2`, for example:

```sh
APP_VERSION=0.1.2 BUILD_NUMBER=3 zsh scripts/prepare-github-release.sh w3ifeng/tethri
```

This builds a universal app, embeds Sparkle and its license, writes the public update settings into the app, and generates an appcast with signed downloads. The ZIP signature is checked against the public key embedded in the app. Missing/mismatched keys, invalid URLs, non-universal apps and reused/decreasing build numbers in the local feed are rejected. A failed preparation preserves the previous feed.

Outputs for this example:

- `build/updates/Tethri-0.1.2-3.zip`
- `build/updates/appcast.xml`
- Release tag: `v0.1.2-3`

Preserve `build/updates` between releases to retain history. On a fresh release machine, download the prior `appcast.xml` into this folder first and use a build number greater than every published build. Never overwrite a published ZIP; increment the build number.

Create a release using the printed tag, upload the new ZIP and `appcast.xml`, then publish it as a normal release marked **Latest**. Use a draft while uploading so a live feed cannot point at an incomplete release. The appcast's archive links use version-specific URLs; the feed itself uses GitHub's [latest-release asset link](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases). Drafts and prereleases cannot serve this stable feed.

With an authenticated GitHub CLI:

```sh
gh release create v0.1.2-3 \
  build/updates/Tethri-0.1.2-3.zip build/updates/appcast.xml \
  --repo w3ifeng/tethri --title 'Tethri 0.1.2' \
  --notes 'Describe the changes here.' --draft

# After reviewing the draft:
gh release edit v0.1.2-3 --repo w3ifeng/tethri --draft=false --latest
```

The repository needs at least one commit before a release can be created; a download README is enough. A published release must include an asset named exactly `appcast.xml`.

For Apple signing/notarization, add `DEVELOPER_ID` and `NOTARY_PROFILE` to the preparation command. Sparkle's nested helpers are signed before its framework and the host app. Stapling happens before archiving/signing the update, so its signature covers the exact bytes uploaded. Without Apple credentials, builds use ad-hoc signing and initial installs may need macOS's Open Anyway approval. Sparkle signatures protect downloads but do not replace Gatekeeper trust.

## Other HTTPS hosting and release notes

Edit `updates.json` for a different stable HTTPS feed, or pass `UPDATE_FEED_URL` and `UPDATE_PUBLIC_KEY` at build time. `APP_VERSION` and `BUILD_NUMBER` override the source plist version; build numbers are positive integers.

```sh
APP_VERSION=0.1.2 BUILD_NUMBER=3 UNIVERSAL=1 scripts/build-app.sh
python3 scripts/prepare-update.py \
  --download-url-prefix https://downloads.example.com/tethri/ \
  --notes /path/to/release-notes.md
```

`--account` selects another Keychain account; `--key-file` supports signing outside Keychain. The default account is `tethri`. Upload separate release-note files alongside archives. Preparation validates a staging feed/signature before atomically replacing `build/updates/appcast.xml`. Neither preparation script publishes files.

## Verification

```sh
python3 scripts/test-updater.py
UNIVERSAL=1 scripts/build-app.sh
python3 scripts/test-updater.py --integration
```

The integration tests start the actual updater class in a temporary app with isolated preferences and automatic requests disabled, checking startup, Settings preference observation, menu validation and session deferral. They also use an ephemeral key and temporary copy of the universal app to generate a real signed appcast, without reading/changing the production Keychain key. CryptoKit checks the ZIP against the embedded public key. Tests cover tampering, wrong public keys, and preserving a feed when a build number is reused. Sparkle's generator uses its ordinary user cache directory.

Before broad distribution, test a downloaded upgrade on another Mac/user account:

1. Install the older updater-enabled build in `/Applications`, approve initial macOS trust/Chrome permissions, and change a preference.
2. Start a focus session and confirm it has a resumable checkpoint.
3. Publish a higher-build-number test release with its signed ZIP and appcast, using a separate test repository/feed if needed. Keep the signing key consistent.
4. Select **Check for Updates…**, confirm the offered version, install and relaunch.
5. Confirm the version changes, preferences persist, the interrupted session resumes, and Chrome Automation behaves as expected. Chat history is not persisted.
6. Check an offline/404 feed reports an update error without interfering with the timer/chat.
7. Disable automatic checks and restart; verify the toggle persists and manual checks still work.

The automated test does not exercise Sparkle's interactive installer/relaunch, another Mac's Gatekeeper, or Apple notarization.
