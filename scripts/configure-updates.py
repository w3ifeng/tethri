#!/usr/bin/env python3
"""Validate public update configuration and write it into a built app (no private keys)."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]


def https_url(value):
    url = urlsplit(value)
    # Accessing .port also rejects malformed and out-of-range ports.
    port = url.port
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment or any(c.isspace() for c in value):
        raise ValueError("Update URLs must be HTTPS URLs without credentials, fragments or whitespace")
    return value


def configure(info, config, env, disabled=False):
    info = dict(info)
    for name, key in [("APP_VERSION", "CFBundleShortVersionString"), ("BUILD_NUMBER", "CFBundleVersion")]:
        value = env.get(name, info[key])
        pattern = r"[0-9]+(?:\.[0-9]+){0,2}" if name == "APP_VERSION" else r"[1-9][0-9]*"
        if not re.fullmatch(pattern, value):
            raise ValueError(f"{name} must be {'a numeric version such as 0.2.0' if name == 'APP_VERSION' else 'a positive integer'}")
        info[key] = value
    for key in ("SUFeedURL", "SUPublicEDKey"):
        info.pop(key, None)
    feed = env.get("UPDATE_FEED_URL", config.get("feedURL", "")).strip()
    key = env.get("UPDATE_PUBLIC_KEY", config.get("publicEDKey", "")).strip()
    if not disabled and (feed or key):
        https_url(feed)
        if len(base64.b64decode(key, validate=True)) != 32:
            raise ValueError("UPDATE_PUBLIC_KEY / publicEDKey must be a base64-encoded 32-byte Ed25519 public key")
        info.update(SUFeedURL=feed, SUPublicEDKey=key)
    info.update(SUEnableAutomaticChecks=bool(not disabled and feed and key),
                SUScheduledCheckInterval=86400, SUAutomaticallyUpdate=False,
                SUAllowsAutomaticUpdates=False, SUEnableSystemProfiling=False,
                SUVerifyUpdateBeforeExtraction=True)
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--disable", action="store_true", help="Disable updates for isolated previews")
    args = parser.parse_args()
    path = args.app / "Contents/Info.plist"
    try:
        config = json.loads((ROOT / "updates.json").read_text())
        info = configure(plistlib.loads(path.read_bytes()), config, os.environ, args.disable)
        path.write_bytes(plistlib.dumps(info))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(1, f"Update configuration error: {error}\n")


if __name__ == "__main__":
    main()
