#!/usr/bin/env python3
"""Updater configuration tests; --integration also tests a real signed universal app release."""
import base64
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


config = load("update_config", ROOT / "scripts/configure-updates.py")
release = load("update_release", ROOT / "scripts/prepare-update.py")
PUBLIC = base64.b64encode(bytes(range(32))).decode()
INFO = {"CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"}
CONFIG = {"feedURL": "https://example.com/appcast.xml", "publicEDKey": PUBLIC}


class ConfigurationTests(unittest.TestCase):
    def test_unconfigured_build_does_not_check_or_keep_stale_feed(self):
        result = config.configure(dict(INFO, SUFeedURL="https://old.example/feed", SUPublicEDKey=PUBLIC), {}, {})
        self.assertNotIn("SUFeedURL", result)
        self.assertNotIn("SUPublicEDKey", result)
        self.assertFalse(result["SUEnableAutomaticChecks"])

    def test_preview_never_checks_even_with_release_configuration(self):
        result = config.configure(INFO, CONFIG, {}, disabled=True)
        self.assertNotIn("SUFeedURL", result)
        self.assertFalse(result["SUEnableAutomaticChecks"])

    def test_release_requires_signed_download_and_explicit_installation(self):
        result = config.configure(INFO, CONFIG, {})
        self.assertTrue(result["SUVerifyUpdateBeforeExtraction"])
        self.assertFalse(result["SUAutomaticallyUpdate"])
        self.assertFalse(result["SUAllowsAutomaticUpdates"])
        self.assertFalse(result["SUEnableSystemProfiling"])
        self.assertTrue(result["SUEnableAutomaticChecks"])

    def test_unsafe_feed_urls_are_rejected(self):
        for url in ("http://example.com/feed", "https://u:p@example.com/feed", "https://example.com/feed#fragment", "https://example.com/a b", "https:///feed", "https://example.com:invalid/feed"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                config.configure(INFO, dict(CONFIG, feedURL=url), {})

    def test_partial_configuration_is_rejected(self):
        for value in ({"feedURL": CONFIG["feedURL"]}, {"publicEDKey": PUBLIC}):
            with self.assertRaises(ValueError):
                config.configure(INFO, value, {})

    def test_invalid_public_keys_are_rejected(self):
        for key in ("secret", base64.b64encode(b"short").decode(), "!" * 44):
            with self.assertRaises(ValueError):
                config.configure(INFO, dict(CONFIG, publicEDKey=key), {})

    def test_build_numbers_and_versions_are_validated(self):
        for name, value in (("BUILD_NUMBER", "0"), ("BUILD_NUMBER", "1.5"), ("BUILD_NUMBER", "-1"), ("APP_VERSION", "../../oops")):
            with self.assertRaises(ValueError):
                config.configure(INFO, {}, {name: value})
        result = config.configure(INFO, {}, {"APP_VERSION": "0.2.0", "BUILD_NUMBER": "2"})
        self.assertEqual(result["CFBundleVersion"], "2")


class IntegrationTests(unittest.TestCase):
    def test_packaged_updater_startup_and_preferences(self):
        with tempfile.TemporaryDirectory(prefix="tethri-updater-startup-") as temporary:
            app = Path(temporary) / "Updater Checks.app"
            macos = app / "Contents/MacOS"
            macos.mkdir(parents=True)
            framework = ROOT / ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
            release.run("ditto", framework, app / "Contents/Frameworks/Sparkle.framework")
            info = config.configure(dict(INFO, CFBundleIdentifier="com.focuscompanion.mac", CFBundleExecutable="checks"), CONFIG, {})
            info.update(SUEnableAutomaticChecks=False, SUDefaultsDomain="com.focuscompanion.updater-checks." + str(uuid.uuid4()))
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT / ".build/clang-cache"))
            release.run("swiftc", ROOT / "Sources/FocusCompanion/AppUpdater.swift", ROOT / "Tests/UpdaterChecks/main.swift",
                        "-F", framework.parent, "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker",
                        "@executable_path/../Frameworks", "-o", macos / "checks", env=env)
            release.run("codesign", "--force", "--sign", "-", app)
            release.run(macos / "checks")

    def test_real_signed_release_and_tamper_rejection(self):
        app_source = ROOT / "build/Tethri.app"
        self.assertTrue(app_source.is_dir(), "Build with UNIVERSAL=1 first")
        with tempfile.TemporaryDirectory(prefix="tethri-update-test-") as temporary:
            scratch = Path(temporary)
            # Ephemeral test key; never reads or changes the release key in the user's Keychain.
            source = scratch / "key.swift"
            source.write_text('''import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try key.rawRepresentation.base64EncodedData().write(to: directory.appendingPathComponent("private.key"))
try key.publicKey.rawRepresentation.base64EncodedData().write(to: directory.appendingPathComponent("public.key"))
''')
            env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT / ".build/clang-cache"))
            release.run("swiftc", source, "-o", scratch / "keygen", env=env)
            release.run(scratch / "keygen", scratch)
            private = scratch / "private.key"
            private.chmod(0o600)
            public = (scratch / "public.key").read_text()
            app = scratch / "Tethri.app"
            release.run("ditto", app_source, app)
            plist = app / "Contents/Info.plist"
            info = config.configure(plistlib.loads(plist.read_bytes()), dict(CONFIG, publicEDKey=public),
                                    {"APP_VERSION": "0.1.0", "BUILD_NUMBER": "1"})
            plist.write_bytes(plistlib.dumps(info))
            release.run("codesign", "--force", "--sign", "-", app)
            output = scratch / "updates"
            prefix = "https://example.com/releases/v1/"
            release.prepare(app, output, prefix, key_file=private)
            archive = output / "Tethri-0.1.0-1.zip"
            signature = release.validate_feed(output / "appcast.xml", archive, info, prefix)
            release.verify_update(public, archive, signature)
            with self.assertRaises(subprocess.CalledProcessError):
                release.verify_update(PUBLIC, archive, signature)
            original_feed = (output / "appcast.xml").read_bytes()
            # Reusing or downgrading the build must not overwrite a working release feed.
            with self.assertRaisesRegex(ValueError, "BUILD_NUMBER"):
                release.prepare(app, output, prefix, key_file=private)
            self.assertEqual((output / "appcast.xml").read_bytes(), original_feed)
            with archive.open("ab") as handle:
                handle.write(b"tampered")
            with self.assertRaises(subprocess.CalledProcessError):
                release.verify_update(public, archive, signature)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ConfigurationTests)
    if "--integration" in sys.argv:
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(IntegrationTests))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
