#!/usr/bin/env python3
"""Offline bundle audit. Never signs, installs, authenticates, or uploads.

Exit 2 with --require-release when mandatory configuration/build gates are absent.
Runtime/live/hardware approvals must still be recorded separately by a person.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import plistlib
import re
import subprocess


TEAM = "VA9D6XP354"
APP_ID = "rehan.Suzzme"
PRESENCE_ID = "rehan.Suzzme.Presence"
MAX_PLIST_BYTES = 4 * 1024 * 1024


def command(args):
    try:
        p = subprocess.run(args, capture_output=True, timeout=30)
        return p.returncode, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired):
        return 1, b"", b"Diagnostic unavailable or timed out"


def read_plist(path):
    try:
        if path.stat().st_size > MAX_PLIST_BYTES:
            return {}
        value = plistlib.loads(path.read_bytes())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, plistlib.InvalidFileException):
        return {}


def code_details(path, expected_id, deep=False):
    verify = ["codesign", "--verify", "--strict"]
    if deep:
        verify.append("--deep")
    rc, _, _ = command([*verify, str(path)])
    status, _, data = command(["codesign", "--display", "--verbose=4", str(path)])
    signature = data.decode(errors="replace")
    team = re.search(r"^TeamIdentifier=(.+)$", signature, re.M)
    identifier = re.search(r"^Identifier=(.+)$", signature, re.M)
    ent_status, ent_data, _ = command(["codesign", "--display", "--entitlements", "-", "--xml", str(path)])
    try:
        e = plistlib.loads(ent_data) if ent_status == 0 and len(ent_data) <= MAX_PLIST_BYTES else {}
        if not isinstance(e, dict):
            e = {}
    except (ValueError, plistlib.InvalidFileException):
        e = {}
    result = {"valid": path.exists() and rc == 0 and status == 0 and "Signature=adhoc" not in signature,
              "expectedIdentity": bool(identifier and identifier.group(1) == expected_id),
              "sameTeam": bool(team and team.group(1) == TEAM),
              "team": team.group(1) if team else None,
              "identifier": identifier.group(1) if identifier else None,
              "hardenedRuntime": "(runtime)" in signature,
              "entitlements": e}
    return result


def debuggable(entitlements):
    # Apple uses different entitlement names on macOS and the other platforms.
    return any(entitlements.get(k, False) not in (False, None)
               for k in ("com.apple.security.get-task-allow", "get-task-allow"))


def no_debug_payload(bundle):
    return not any(bundle.rglob("*.debug.dylib"))


def browser_configuration_valid(value):
    if not isinstance(value, dict) or value.get("teamID") != TEAM:
        return False
    group = value.get("appGroup")
    extensions = value.get("extensionIDs")
    # Match BrowserBridgeConfiguration.valid in the shipping Swift owner.
    return (isinstance(group, str) and group.startswith(TEAM + ".")
            and len(group.encode("utf-8")) <= 160 and re.fullmatch(r"[A-Za-z0-9.-]+", group) is not None
            and isinstance(extensions, list) and 1 <= len(extensions) <= 4
            and all(isinstance(v, str) and re.fullmatch(r"[a-p]{32}", v) for v in extensions))


def authorized_value(actual, allowed):
    if isinstance(actual, str):
        return isinstance(allowed, str) and (actual == allowed or
               allowed.endswith("*") and allowed.count("*") == 1 and actual.startswith(allowed[:-1]))
    if isinstance(actual, bool):
        return actual is False or allowed is True
    if isinstance(actual, list):
        return isinstance(allowed, list) and all(any(authorized_value(v, a) for a in allowed) for v in actual)
    if isinstance(actual, dict):
        return isinstance(allowed, dict) and all(authorized_value(v, allowed.get(k)) for k, v in actual.items())
    return actual == allowed


def mac_unrestricted(key, value):
    # TN3125: Sandbox/Hardened Runtime and team-prefixed macOS IPC groups do
    # not by themselves require a profile. Keychain access groups do.
    if key == "com.apple.security.application-groups":
        return isinstance(value, list) and all(isinstance(v, str) and v.startswith(TEAM + ".") for v in value)
    return key.startswith("com.apple.security.")


def profile_details(bundle, platform, bundle_id, entitlements):
    required = platform == "ios" or any(not mac_unrestricted(k, v) and v not in (False, None, [], {})
                                        for k, v in entitlements.items())
    path = bundle / ("Contents/embedded.provisionprofile" if platform == "macos" else "embedded.mobileprovision")
    detail = {"present": path.is_file(), "required": required, "status": "missing", "valid": not required}
    if not detail["present"]:
        return detail
    detail["valid"] = False
    try:
        if path.stat().st_size > MAX_PLIST_BYTES:
            detail["status"] = "oversized"
            return detail
    except OSError:
        detail["status"] = "unreadable"
        return detail
    status, payload, _ = command(["security", "cms", "-D", "-i", str(path)])
    if status != 0 or len(payload) > MAX_PLIST_BYTES:
        detail["status"] = "decode_failed"
        return detail
    try:
        profile = plistlib.loads(payload)
        if not isinstance(profile, dict):
            raise ValueError("Not a profile dictionary")
    except (ValueError, plistlib.InvalidFileException):
        detail["status"] = "invalid_payload"
        return detail
    now = datetime.datetime.now(datetime.timezone.utc)

    def utc(value):
        if not isinstance(value, datetime.datetime):
            return None
        return value.replace(tzinfo=datetime.timezone.utc) if value.tzinfo is None else value.astimezone(datetime.timezone.utc)

    created, expires = utc(profile.get("CreationDate")), utc(profile.get("ExpirationDate"))
    allowed = profile.get("Entitlements", {})
    if not isinstance(allowed, dict):
        allowed = {}
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    app_key = "com.apple.application-identifier" if platform == "macos" else "application-identifier"
    actual_id = entitlements.get(app_key)
    exact_id = isinstance(prefixes, list) and any(isinstance(p, str) and actual_id == p + "." + bundle_id for p in prefixes)
    checks = {"current": bool(created and expires and created <= now < expires),
              "team": profile.get("TeamIdentifier") == [TEAM] and allowed.get("com.apple.developer.team-identifier") == TEAM,
              "platform": isinstance(profile.get("Platform"), list) and
                          ("iOS" in profile["Platform"] if platform == "ios" else any(p in profile["Platform"] for p in ("OSX", "macOS"))),
              "exactSignedAppIdentifier": bool(exact_id and authorized_value(actual_id, allowed.get(app_key))),
              # An embedded Mac profile must also authorize App Groups. An
              # unauthorized group clears entitlements-validated, preventing
              # Data Protection Keychain access (Apple DTS thread 721701).
              "entitlementsAuthorized": all(mac_unrestricted(k, v) and platform == "macos" and k != "com.apple.security.application-groups" or authorized_value(v, allowed.get(k))
                                            for k, v in entitlements.items())}
    # Only bounded, nonsecret conclusions leave this function. No profile
    # payload, device IDs, certificate bytes, profile names or UUIDs are reported.
    detail.update({"status": "inspected", "expirationUTC": expires.isoformat() if expires else None,
                   "checks": checks, "valid": all(checks.values())})
    return detail


def audit(app, platform):
    contents = app / "Contents" if platform == "macos" else app
    info = read_plist(contents / "Info.plist")
    resources = contents / "Resources" if platform == "macos" else app
    gates = {}
    detail = {"bundleID": info.get("CFBundleIdentifier"), "platform": platform,
              "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion")}
    gates["bundle_identity"] = info.get("CFBundleIdentifier") == APP_ID
    required = ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription",
                "NSCalendarsFullAccessUsageDescription", "NSRemindersFullAccessUsageDescription"]
    gates["permission_descriptions"] = all(isinstance(info.get(k), str) and info[k].strip() for k in required)
    cid = info.get("GIDClientID", "")
    cid = cid if isinstance(cid, str) else ""
    reverse = ".".join(reversed(cid.split(".")))
    url_types = info.get("CFBundleURLTypes", [])
    schemes = [s for e in url_types if isinstance(e, dict) for s in e.get("CFBundleURLSchemes", []) if isinstance(s, str)] if isinstance(url_types, list) else []
    gates["google_public_configuration"] = bool(cid.endswith(".apps.googleusercontent.com") and "YOUR_" not in cid and "$" not in cid and reverse in schemes)
    gates["google_client_secret_absent"] = not any("secret" in key.lower() for key in info)
    manifests = []
    for p in sorted(resources.rglob("PrivacyInfo.xcprivacy")):
        d = read_plist(p)
        manifests.append({"path": str(p.relative_to(resources)), "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
                          "tracking": d.get("NSPrivacyTracking"),
                          "requiredReasons": d.get("NSPrivacyAccessedAPITypes", []),
                          "collectedCategories": [x.get("NSPrivacyCollectedDataType") for x in d.get("NSPrivacyCollectedDataTypes", [])]})
    detail["privacyManifests"] = manifests
    gates["app_privacy_manifest"] = bool(read_plist(resources / "PrivacyInfo.xcprivacy"))
    gates["google_sdk_privacy_manifest"] = any("GoogleSignIn_GoogleSignIn.bundle/" in v["path"] for v in manifests)
    main_code = code_details(app, APP_ID, deep=True)
    detail["team"] = main_code["team"]
    detail["signatureIdentifier"] = main_code["identifier"]
    gates["genuine_signature"] = main_code["valid"] and main_code["expectedIdentity"] and main_code["sameTeam"]
    e = main_code["entitlements"]
    detail["entitlements"] = e
    gates["release_not_debuggable"] = not debuggable(e) and no_debug_payload(app)
    detail["provisioning"] = profile_details(app, platform, APP_ID, e)
    gates["provisioning_profile"] = detail["provisioning"]["valid"]
    if platform == "macos":
        gates["sandbox"] = e.get("com.apple.security.app-sandbox") is True
        gates["hardened_runtime"] = main_code["hardenedRuntime"]
        own_id = e.get("com.apple.application-identifier", TEAM + "." + APP_ID)
        gates["app_only_keychain_group"] = isinstance(own_id, str) and own_id.endswith("." + APP_ID) and "*" not in own_id and e.get("keychain-access-groups", []) == [own_id]
        config = resources / "BrowserBridge.json"
        try:
            c = json.loads(config.read_text()) if config.stat().st_size <= 4096 else {}
        except (OSError, ValueError):
            c = {}
        configured = browser_configuration_valid(c)
        gates["browser_public_configuration"] = bool(configured)
        gates["browser_app_group"] = bool(configured and c["appGroup"] in e.get("com.apple.security.application-groups", []))
        helpers = []
        for name, suffix in [("SuzzmeBrowserHost", "BrowserHost"), ("SuzzmeBrowserBroker", "BrowserBroker")]:
            p = contents / "MacOS" / name
            helper_code = code_details(p, f"{APP_ID}.{suffix}")
            helper_entitlements = helper_code["entitlements"]
            helpers.append({"name":name,"valid":p.is_file() and helper_code["valid"],
                "expectedIdentity": helper_code["expectedIdentity"],
                "sameTeam": helper_code["sameTeam"],
                "hardenedRuntime": helper_code["hardenedRuntime"],
                "releaseNotDebuggable": not debuggable(helper_entitlements),
                "sandbox": helper_entitlements.get("com.apple.security.app-sandbox") is True,
                "configuredAppGroup": bool(configured and c["appGroup"] in helper_entitlements.get("com.apple.security.application-groups", []))})
        detail["helpers"] = helpers
        gates["signed_nested_helpers"] = all(x["valid"] and x["expectedIdentity"] and x["sameTeam"] for x in helpers)
        gates["browser_helper_entitlements"] = all(x["hardenedRuntime"] and x["sandbox"] and x["configuredAppGroup"] and x["releaseNotDebuggable"] for x in helpers)
    else:
        gates["live_activity_declared"] = info.get("NSSupportsLiveActivities") is True
        widgets = list((app / "PlugIns").glob("*.appex"))
        presence = [w for w in widgets if read_plist(w / "Info.plist").get("CFBundleIdentifier") == PRESENCE_ID]
        gates["presence_extension_embedded"] = len(presence) == 1
        extension_codes = [code_details(w, PRESENCE_ID, deep=True) for w in presence]
        gates["signed_presence_extension"] = len(extension_codes) == 1 and all(x["valid"] and x["expectedIdentity"] and x["sameTeam"] for x in extension_codes)
        gates["presence_extension_release"] = len(extension_codes) == 1 and all(not debuggable(x["entitlements"]) and no_debug_payload(w) for w, x in zip(presence, extension_codes))
        extension_profiles = [profile_details(w, "ios", PRESENCE_ID, x["entitlements"]) for w, x in zip(presence, extension_codes)]
        gates["presence_extension_provisioning"] = len(extension_profiles) == 1 and all(x["valid"] for x in extension_profiles)
        detail["presenceExtension"] = [{"signatureIdentifier": x["identifier"], "team": x["team"], "provisioning": p}
                                       for x, p in zip(extension_codes, extension_profiles)]
        gates["ios_device_platform"] = info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"]
        gates["no_mac_helpers_in_ios"] = not (app / "Contents").exists()
    return {"schema":1,"app":str(app),"gates":gates,"details":detail,
            "missingBuildConfigurationGates":[k for k,v in gates.items() if not v],
            "releaseReady":False,"remainingAcceptance":"Live accounts, MCP, installed browser, hardware, privacy review and distribution still require separate acceptance."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--platform", choices=["macos", "ios"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--require-release", action="store_true")
    args = parser.parse_args()
    result = audit(args.app, args.platform)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"missingGates":result["missingBuildConfigurationGates"], "releaseReady":False}))
    return 2 if args.require_release and result["missingBuildConfigurationGates"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
