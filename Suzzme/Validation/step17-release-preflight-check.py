#!/usr/bin/env python3
"""Offline negative acceptance checks. Synthetic code/profile responses only."""
import datetime
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("preflight", Path(__file__).with_name("release-preflight.py"))
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)
old_spec = importlib.util.spec_from_file_location("old_checks", Path(__file__).with_name("step16-release-preflight-check.py"))
old_checks = importlib.util.module_from_spec(old_spec)
old_spec.loader.exec_module(old_checks)
TEAM = "VA9D6XP354"
APP_ID = "rehan.Suzzme"
PRESENCE_ID = "rehan.Suzzme.Presence"


def profile(bundle_id, platform="iOS"):
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    key = "application-identifier" if platform == "iOS" else "com.apple.application-identifier"
    return {"TeamIdentifier": [TEAM], "ApplicationIdentifierPrefix": [TEAM], "Platform": [platform],
            "CreationDate": now - datetime.timedelta(days=1), "ExpirationDate": now + datetime.timedelta(days=30),
            "Entitlements": {key: f"{TEAM}.{bundle_id}", "com.apple.developer.team-identifier": TEAM,
                             "keychain-access-groups": [f"{TEAM}.*"], "get-task-allow": True}}


class IOSBundleAuditChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="SuzzmeStep17ReleaseCheck-")
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "Suzzme.app"
        self.widget = self.app / "PlugIns/SuzzmePresenceWidget.appex"
        self.widget.mkdir(parents=True)
        self.info = {"CFBundleIdentifier": APP_ID, "GIDClientID": "fixture.apps.googleusercontent.com",
                     "CFBundleURLTypes": [{"CFBundleURLSchemes": ["com.googleusercontent.apps.fixture"]}],
                     "NSSupportsLiveActivities": True, "CFBundleSupportedPlatforms": ["iPhoneOS"]}
        for key in ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription",
                    "NSCalendarsFullAccessUsageDescription", "NSRemindersFullAccessUsageDescription"]:
            self.info[key] = "Permission purpose"
        (self.widget / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": PRESENCE_ID}))
        for manifest in [self.app / "PrivacyInfo.xcprivacy", self.app / "GoogleSignIn_GoogleSignIn.bundle/PrivacyInfo.xcprivacy"]:
            manifest.parent.mkdir(parents=True, exist_ok=True)
            manifest.write_bytes(plistlib.dumps({"NSPrivacyTracking": False}))
        self.code = {}
        self.profiles = {}
        for bundle, identifier in [(self.app, APP_ID), (self.widget, PRESENCE_ID)]:
            entitlements = {"application-identifier": f"{TEAM}.{identifier}",
                            "com.apple.developer.team-identifier": TEAM, "get-task-allow": False}
            if bundle == self.app:
                entitlements["keychain-access-groups"] = [f"{TEAM}.{identifier}"]
            self.code[str(bundle)] = {"team": TEAM, "identifier": identifier, "verifyExit": 0,
                                      "entitlements": entitlements}
            embedded = bundle / "embedded.mobileprovision"
            embedded.write_bytes(b"synthetic-profile")
            self.profiles[str(embedded)] = profile(identifier)

    def command(self, args):
        if args[:3] == ["security", "cms", "-D"]:
            return 0, plistlib.dumps(self.profiles[args[-1]]), b""
        code = self.code.get(args[-1], {})
        if "--verify" in args:
            return code.get("verifyExit", 1), b"", b""
        if "--entitlements" in args:
            return 0, plistlib.dumps(code.get("entitlements", {})), b""
        return 0, b"", f"TeamIdentifier={code.get('team')}\nIdentifier={code.get('identifier')}\n".encode()

    def result(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))
        with patch.object(preflight, "command", self.command):
            return preflight.audit(self.app, "ios")

    def test_complete_device_configuration_keeps_runtime_pending(self):
        result = self.result()
        self.assertEqual(result["missingBuildConfigurationGates"], [])
        self.assertFalse(result["releaseReady"])

    def test_ios_debug_entitlement_rejected(self):
        self.code[str(self.app)]["entitlements"]["get-task-allow"] = True
        self.assertFalse(self.result()["gates"]["release_not_debuggable"])

    def test_signature_identifier_must_match_app(self):
        self.code[str(self.app)]["identifier"] = "rehan.Suzzme.other"
        self.assertFalse(self.result()["gates"]["genuine_signature"])

    def test_extension_team_must_match_app(self):
        self.code[str(self.widget)]["team"] = "OTHERTEAM1"
        self.assertFalse(self.result()["gates"].get("signed_presence_extension", True))

    def test_extension_identifier_must_match_expected_bundle(self):
        self.code[str(self.widget)]["identifier"] = PRESENCE_ID + ".other"
        self.assertFalse(self.result()["gates"].get("signed_presence_extension", True))

    def test_extension_invalid_signature_rejected(self):
        self.code[str(self.widget)]["verifyExit"] = 1
        self.assertFalse(self.result()["gates"].get("signed_presence_extension", True))

    def test_extension_debug_entitlement_rejected(self):
        self.code[str(self.widget)]["entitlements"]["get-task-allow"] = True
        self.assertFalse(self.result()["gates"].get("presence_extension_release", True))

    def test_extension_debug_library_rejected(self):
        (self.widget / "SuzzmePresenceWidget.debug.dylib").touch()
        self.assertFalse(self.result()["gates"].get("presence_extension_release", True))

    def test_duplicate_presence_extension_rejected(self):
        other = self.app / "PlugIns/Duplicate.appex"
        other.mkdir()
        (other / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": PRESENCE_ID}))
        self.assertFalse(self.result()["gates"]["presence_extension_embedded"])

    def test_main_profile_missing_rejected(self):
        (self.app / "embedded.mobileprovision").unlink()
        self.assertFalse(self.result()["gates"].get("provisioning_profile", True))

    def test_extension_profile_missing_rejected(self):
        (self.widget / "embedded.mobileprovision").unlink()
        self.assertFalse(self.result()["gates"].get("presence_extension_provisioning", True))

    def test_expired_profile_rejected(self):
        self.profiles[str(self.app / "embedded.mobileprovision")]["ExpirationDate"] = datetime.datetime(2000, 1, 1)
        self.assertFalse(self.result()["gates"].get("provisioning_profile", True))

    def test_future_profile_rejected(self):
        self.profiles[str(self.app / "embedded.mobileprovision")]["CreationDate"] = datetime.datetime(2100, 1, 1)
        self.assertFalse(self.result()["gates"].get("provisioning_profile", True))

    def test_profile_team_mismatch_rejected(self):
        self.profiles[str(self.app / "embedded.mobileprovision")]["TeamIdentifier"] = ["OTHERTEAM1"]
        self.assertFalse(self.result()["gates"].get("provisioning_profile", True))

    def test_profile_platform_mismatch_rejected(self):
        self.profiles[str(self.app / "embedded.mobileprovision")]["Platform"] = ["OSX"]
        self.assertFalse(self.result()["gates"].get("provisioning_profile", True))

    def test_profile_wrong_bundle_rejected(self):
        self.profiles[str(self.app / "embedded.mobileprovision")]["Entitlements"]["application-identifier"] = f"{TEAM}.other.App"
        self.assertFalse(self.result()["gates"].get("provisioning_profile", True))

    def test_signature_wrong_app_identifier_entitlement_rejected(self):
        self.code[str(self.app)]["entitlements"]["application-identifier"] = f"{TEAM}.other.App"
        self.assertFalse(self.result()["gates"].get("provisioning_profile", True))

    def test_profile_keychain_allowlist_rejected(self):
        self.profiles[str(self.app / "embedded.mobileprovision")]["Entitlements"]["keychain-access-groups"] = [f"{TEAM}.other.App"]
        self.assertFalse(self.result()["gates"].get("provisioning_profile", True))

    def test_profile_safe_summary_does_not_disclose_devices_or_certificates(self):
        data = self.profiles[str(self.app / "embedded.mobileprovision")]
        data["ProvisionedDevices"] = ["private-device-id"]
        data["DeveloperCertificates"] = [b"private-certificate-bytes"]
        result = json.dumps(self.result())
        self.assertNotIn("private-device-id", result)
        self.assertNotIn("private-certificate-bytes", result)

    def test_simulator_is_not_device_distribution(self):
        self.info["CFBundleSupportedPlatforms"] = ["iPhoneSimulator"]
        self.assertFalse(self.result()["gates"].get("ios_device_platform", True))


class MacConfigurationChecks(unittest.TestCase):
    setUp = old_checks.BundleAuditChecks.setUp
    command = old_checks.BundleAuditChecks.command
    result = old_checks.BundleAuditChecks.result

    def test_helper_signature_identifier_suffix_rejected(self):
        original = self.command
        def replaced(args):
            status, output, signature = original(args)
            return status, output, signature.replace(b"Identifier=rehan.Suzzme.BrowserHost\n", b"Identifier=rehan.Suzzme.BrowserHost.extra\n")
        self.command = replaced
        self.assertFalse(self.result()["gates"]["signed_nested_helpers"])

    def test_main_signature_identifier_suffix_rejected(self):
        original = self.command
        def replaced(args):
            status, output, signature = original(args)
            return status, output, signature.replace(b"Identifier=rehan.Suzzme\n", b"Identifier=rehan.Suzzme.extra\n")
        self.command = replaced
        self.assertFalse(self.result()["gates"]["genuine_signature"])

    def test_team_prefixed_group_required(self):
        self.config["appGroup"] = "group.fixture.suzzme"
        self.assertFalse(self.result()["gates"]["browser_public_configuration"])

    def test_group_non_ascii_rejected(self):
        self.config["appGroup"] = TEAM + ".suzzmé"
        self.assertFalse(self.result()["gates"]["browser_public_configuration"])

    def test_group_length_bound_rejected(self):
        self.config["appGroup"] = TEAM + "." + "a" * 160
        self.assertFalse(self.result()["gates"]["browser_public_configuration"])

    def test_extension_count_bound_rejected(self):
        self.config["extensionIDs"] = ["a" * 32] * 5
        self.assertFalse(self.result()["gates"]["browser_public_configuration"])

    def test_malformed_browser_types_rejected_without_crash(self):
        self.config["extensionIDs"] = "a" * 32
        self.assertFalse(self.result()["gates"]["browser_public_configuration"])

    def test_mac_keychain_requires_profile(self):
        (self.contents / "embedded.provisionprofile").unlink(missing_ok=True)
        self.assertFalse(self.result()["gates"].get("provisioning_profile", True))

    def test_mac_keychain_profile_must_authorize_ipc_group(self):
        self.profile["Entitlements"].pop("com.apple.security.application-groups", None)
        self.assertFalse(self.result()["gates"]["provisioning_profile"])

    def test_mac_unrestricted_entitlements_do_not_require_profile(self):
        self.entitlements.pop("keychain-access-groups")
        self.entitlements.pop("com.apple.application-identifier", None)
        self.entitlements.pop("com.apple.developer.team-identifier", None)
        (self.contents / "embedded.provisionprofile").unlink(missing_ok=True)
        self.assertTrue(self.result()["gates"].get("provisioning_profile", False))


if __name__ == "__main__":
    unittest.main(verbosity=2)
