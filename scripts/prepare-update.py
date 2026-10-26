#!/usr/bin/env python3
"""Package a built app and generate a signed Sparkle feed, ready to upload. Publishes nothing."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from importlib.util import module_from_spec, spec_from_file_location

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = ROOT / ".build/artifacts/sparkle/Sparkle/bin"
NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
spec = spec_from_file_location("update_config", ROOT / "scripts/configure-updates.py")
config = module_from_spec(spec)
spec.loader.exec_module(config)


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def validate_feed(path, archive, info, prefix):
    feed = ET.parse(path)
    item = next((item for item in feed.findall("./channel/item")
                 if item.findtext("sparkle:version", namespaces=NS) == info["CFBundleVersion"]), None)
    if item is None:
        raise ValueError("Generated feed is missing the new build")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Generated feed is missing the update download")
    signature = enclosure.get(f"{{{NS['sparkle']}}}edSignature", "")
    if not signature or int(enclosure.get("length", "0")) != archive.stat().st_size:
        raise ValueError("Generated feed has a missing signature or incorrect archive size")
    if enclosure.get("url") != prefix + archive.name:
        raise ValueError("Generated feed has an unexpected download URL")
    return signature


def prepare(app, output, prefix, account="tethri", key_file=None, notes=None):
    prefix = config.https_url(prefix).rstrip("/") + "/"
    # A prefix is a directory URL, not a signed URL or query-based redirect.
    if config.urlsplit(prefix).query:
        raise ValueError("The download URL prefix must not contain a query string")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    info = config.configure(info, {"feedURL": info.get("SUFeedURL", ""),
                                  "publicEDKey": info.get("SUPublicEDKey", "")}, {})
    if not info.get("SUFeedURL") or not info.get("SUPublicEDKey"):
        raise ValueError("Build with a feed URL and public update key before preparing an update")
    if info.get("CFBundleIdentifier") != "com.focuscompanion.mac":
        raise ValueError("Only the production Tethri bundle can be published as an update")
    if not (SPARKLE / "generate_appcast").is_file():
        raise ValueError("Build the app first to download Sparkle's release tools")
    run("codesign", "--verify", "--deep", "--strict", app)
    architectures = run("lipo", "-archs", app / "Contents/MacOS/FocusCompanion", capture_output=True, text=True).stdout.split()
    if not {"arm64", "x86_64"}.issubset(architectures):
        raise ValueError("Build with UNIVERSAL=1 so updates work on both Intel and Apple Silicon Macs")
    output.mkdir(parents=True, exist_ok=True)
    previous = output / "appcast.xml"
    if previous.exists():
        versions = [int(value.text) for value in ET.parse(previous).findall("./channel/item/sparkle:version", NS)]
        if versions and int(info["CFBundleVersion"]) <= max(versions):
            raise ValueError("BUILD_NUMBER must be greater than every version already in the feed")
    filename = f"Tethri-{info['CFBundleShortVersionString']}-{info['CFBundleVersion']}.zip"
    if (output / filename).exists():
        raise ValueError("An archive with this version already exists; increment BUILD_NUMBER")
    # Prepare and validate in a staging directory. An unsuccessful signing run preserves the prior feed.
    with tempfile.TemporaryDirectory(prefix=".tethri-update-", dir=output.parent) as temporary:
        stage = Path(temporary)
        for existing in output.iterdir():
            if existing.is_file() and existing.suffix in {".xml", ".zip", ".html", ".md", ".txt"}:
                shutil.copy2(existing, stage / existing.name)
        archive = stage / filename
        run("ditto", "-c", "-k", "--keepParent", app, archive)
        if notes:
            if notes.suffix not in {".html", ".md", ".txt"}:
                raise ValueError("Release notes must be .html, .md or .txt")
            shutil.copy2(notes, archive.with_suffix(notes.suffix))
        signing = ["--ed-key-file", str(key_file.resolve())] if key_file else ["--account", account]
        run(SPARKLE / "generate_appcast", *signing, "--download-url-prefix", prefix,
            "--maximum-versions", "0", "--maximum-deltas", "0", "-o", stage / "appcast.xml", stage)
        signature = validate_feed(stage / "appcast.xml", archive, info, prefix)
        verify_update(info["SUPublicEDKey"], archive, signature)
        # Copy immutable downloads first; replace the public feed last and atomically.
        for item in stage.iterdir():
            if item.is_file() and item.name != "appcast.xml":
                shutil.copy2(item, output / item.name)
        os.replace(stage / "appcast.xml", output / "appcast.xml")
    print(f"Prepared {output / filename}")
    print(f"Upload downloads to {prefix}, then upload appcast.xml to {info['SUFeedURL']}")
    print("No files have been published. Test an older installed build before announcing this release.")


def verify_update(public_key, archive, signature):
    tools = ROOT / ".build/update-tools"
    tools.mkdir(parents=True, exist_ok=True)
    verifier = tools / "verify-update"
    source = ROOT / "scripts/verify-update.swift"
    if not verifier.exists() or verifier.stat().st_mtime < source.stat().st_mtime:
        env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT / ".build/clang-cache"))
        run("swiftc", source, "-o", verifier, env=env)
    run(verifier, public_key, archive, signature)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "build/Tethri.app")
    parser.add_argument("--output", type=Path, default=ROOT / "build/updates")
    parser.add_argument("--download-url-prefix", required=True, help="HTTPS directory hosting the ZIP files")
    parser.add_argument("--account", default="tethri", help="Sparkle signing key's Keychain account")
    parser.add_argument("--key-file", type=Path, help="Private Sparkle key file (instead of Keychain)")
    parser.add_argument("--notes", type=Path, help="Optional .md, .txt or .html release notes")
    args = parser.parse_args()
    try:
        prepare(args.app.resolve(), args.output.resolve(), args.download_url_prefix,
                args.account, args.key_file, args.notes)
    except (ValueError, OSError, KeyError, TypeError, ET.ParseError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release preparation failed: {error}\n")


if __name__ == "__main__":
    main()
