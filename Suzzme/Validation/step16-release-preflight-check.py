#!/usr/bin/env python3
"""Fail-closed bundle audit checks. Synthetic bundles/signatures; no signing or upload."""
import importlib.util
import datetime
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("preflight", Path(__file__).with_name("release-preflight.py"))
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


class BundleAuditChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="SuzzmeStep16ReleaseCheck-")
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "Suzzme.app"
        self.contents = self.app / "Contents"
        self.resources = self.contents / "Resources"
        self.resources.mkdir(parents=True)
        self.info = {"CFBundleIdentifier": "rehan.Suzzme", "GIDClientID": "fixture.apps.googleusercontent.com",
                     "CFBundleURLTypes": [{"CFBundleURLSchemes": ["com.googleusercontent.apps.fixture"]}]}
        for key in ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription",
                    "NSCalendarsFullAccessUsageDescription", "NSRemindersFullAccessUsageDescription"]:
            self.info[key] = "Permission purpose"
        self.entitlements = {"com.apple.security.app-sandbox": True,
                             "keychain-access-groups": ["VA9D6XP354.rehan.Suzzme"],
                             "com.apple.application-identifier": "VA9D6XP354.rehan.Suzzme",
                             "com.apple.developer.team-identifier": "VA9D6XP354",
                             "com.apple.security.application-groups": ["VA9D6XP354.fixture.suzzme"]}
        now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
        self.profile = {"TeamIdentifier": ["VA9D6XP354"], "ApplicationIdentifierPrefix": ["VA9D6XP354"],
                        "Platform": ["OSX"], "CreationDate": now - datetime.timedelta(days=1),
                        "ExpirationDate": now + datetime.timedelta(days=30),
                        "Entitlements": {"com.apple.application-identifier": "VA9D6XP354.rehan.Suzzme",
                                         "com.apple.developer.team-identifier": "VA9D6XP354",
                                         "keychain-access-groups": ["VA9D6XP354.*"],
                                         "com.apple.security.application-groups": ["VA9D6XP354.*"]}}
        (self.contents / "embedded.provisionprofile").write_bytes(b"synthetic-profile")
        self.team = "VA9D6XP354"
        self.verify_exit = 0
        self.adhoc = False
        self.helper_team = self.team
        self.helper_entitlements = dict(self.entitlements)
        for name in ["SuzzmeBrowserHost", "SuzzmeBrowserBroker"]:
            p = self.contents / "MacOS" / name
            p.parent.mkdir(exist_ok=True)
            p.touch()
        for p in [self.resources / "PrivacyInfo.xcprivacy",
                  self.resources / "GoogleSignIn_GoogleSignIn.bundle/PrivacyInfo.xcprivacy"]:
            p.parent.mkdir(exist_ok=True)
            p.write_bytes(plistlib.dumps({"NSPrivacyTracking": False}))
        self.config = {"teamID": self.team, "appGroup": "VA9D6XP354.fixture.suzzme", "extensionIDs": ["a" * 32]}

    def command(self, args):
        if args[:3] == ["security", "cms", "-D"]:
            return 0, plistlib.dumps(self.profile), b""
        if "--verify" in args:
            return self.verify_exit, b"", b""
        if "--entitlements" in args:
            e = self.helper_entitlements if Path(args[-1]).name.startswith("SuzzmeBrowser") else self.entitlements
            return 0, plistlib.dumps(e), b""
        helper = Path(args[-1]).name
        team = self.helper_team if helper.startswith("SuzzmeBrowser") else self.team
        identity = "rehan.Suzzme." + helper.removeprefix("Suzzme") if helper.startswith("SuzzmeBrowser") else "rehan.Suzzme"
        sig = f"TeamIdentifier={team}\nIdentifier={identity}\nflags=0x10000(runtime)\n"
        if self.adhoc:
            sig += "Signature=adhoc\n"
        return 0, b"", sig.encode()

    def result(self):
        (self.contents / "Info.plist").write_bytes(plistlib.dumps(self.info))
        (self.resources / "BrowserBridge.json").write_text(json.dumps(self.config))
        with patch.object(preflight, "command", self.command):
            return preflight.audit(self.app, "macos")

    def test_complete_configuration_never_implies_runtime_acceptance(self):
        r = self.result()
        self.assertEqual(r["missingBuildConfigurationGates"], [])
        self.assertFalse(r["releaseReady"])

    def test_failed_verification_rejected(self):
        self.verify_exit = 1
        self.assertFalse(self.result()["gates"]["genuine_signature"])

    def test_wrong_team_rejected(self):
        self.team = "OTHERTEAM"
        self.assertFalse(self.result()["gates"]["genuine_signature"])

    def test_ad_hoc_signature_rejected(self):
        self.adhoc = True
        self.assertFalse(self.result()["gates"]["genuine_signature"])

    def test_debug_entitlement_rejected(self):
        self.entitlements["com.apple.security.get-task-allow"] = True
        self.assertFalse(self.result()["gates"]["release_not_debuggable"])

    def test_debug_library_rejected(self):
        (self.contents / "MacOS/Suzzme.debug.dylib").touch()
        self.assertFalse(self.result()["gates"]["release_not_debuggable"])

    def test_placeholder_google_client_rejected(self):
        self.info["GIDClientID"] = "YOUR_CLIENT.apps.googleusercontent.com"
        self.assertFalse(self.result()["gates"]["google_public_configuration"])

    def test_wrong_callback_rejected(self):
        self.info["CFBundleURLTypes"] = [{"CFBundleURLSchemes": ["wrong"]}]
        self.assertFalse(self.result()["gates"]["google_public_configuration"])

    def test_missing_keychain_group_rejected(self):
        self.entitlements.pop("keychain-access-groups")
        self.assertFalse(self.result()["gates"]["app_only_keychain_group"])

    def test_unentitled_browser_group_rejected(self):
        self.entitlements.pop("com.apple.security.application-groups")
        self.assertFalse(self.result()["gates"]["browser_app_group"])

    def test_invalid_extension_identity_rejected(self):
        self.config["extensionIDs"] = ["z" * 32]
        self.assertFalse(self.result()["gates"]["browser_public_configuration"])

    def test_replaced_helper_team_rejected(self):
        self.helper_team = "OTHERTEAM"
        self.assertFalse(self.result()["gates"]["signed_nested_helpers"])

    def test_extra_keychain_group_rejected(self):
        self.entitlements["keychain-access-groups"] = ["VA9D6XP354.rehan.Suzzme", "VA9D6XP354.other"]
        self.assertFalse(self.result()["gates"]["app_only_keychain_group"])

    def test_missing_helper_group_rejected(self):
        self.helper_entitlements.pop("com.apple.security.application-groups")
        self.assertFalse(self.result()["gates"]["browser_helper_entitlements"])

    def test_unsandboxed_helper_rejected(self):
        self.helper_entitlements["com.apple.security.app-sandbox"] = False
        self.assertFalse(self.result()["gates"]["browser_helper_entitlements"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
