# Suzzme release handoff

These procedures are prepared, not executed acceptance. No account registration, provisioning update, provider sign-in, browser installation, notarization submission or upload is authorized by this document alone. Run commands from the repository root.

## Required configuration

The inspected project uses team `VA9D6XP354`, app `rehan.Suzzme`, and iOS extension `rehan.Suzzme.Presence`. Confirm ownership before distributing. A genuine Apple Development identity is present; matching app provisioning profiles and a Developer ID distribution identity were not found during Step 16.

- Verify the public `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_IOS_REVERSED_CLIENT_ID`, `GOOGLE_MACOS_CLIENT_ID` and `GOOGLE_MACOS_REVERSED_CLIENT_ID` values in Debug and Release against registered native OAuth clients. `GmailOAuthInfo.plist` consumes the platform-selected values. Never add a client secret. Test the callback and both Gmail consent grants (`gmail.metadata` and optional `gmail.readonly`) on each platform. [Google native setup](https://developers.google.com/identity/sign-in/ios/start-integrating).
- The macOS entitlement file now declares the app's own Keychain access group. Provision the correct signed app; do not remove the entitlement to make signing pass.
- For the browser bridge, obtain the actual Chrome extension ID and choose the real macOS IPC group required by the existing bridge policy: it must start with `VA9D6XP354.`. A team-prefixed macOS IPC group is not a portal-allocated `group.*` identifier. The main app already requires a profile for its Keychain group; that profile must authorize its App Groups entitlement (current profiles can use `TEAM_ID.*`). Enable the App Groups capability for the actual app/profile where needed rather than inventing a portal group. Create local configuration JSON with `teamID`, `appGroup` and `extensionIDs`, supply its absolute path through `SUZZME_BROWSER_CONFIG`, and use the same chosen group in the app/helper entitlements. Empty configuration intentionally disables the bridge. Never invent an extension ID or silently choose a shared group. [Apple macOS App Groups guidance](https://developer.apple.com/forums/thread/721701).
- Enable only the Google APIs and read scopes for the explicitly selected services. Complete the consent screen, test-user registration and applicable verification. Account/resource consent must happen in Suzzme. Store no tokens in export configuration.
- Use a specifically trusted HTTPS MCP server compatible with the current pinned read-only transport. Enter any server credential only in Suzzme. Unsupported stdio, local commands and write tools stay disabled.

## Local compilation and bundle audit

The Step 16 validation report records the exact cache-preserving commands already executed. For a configured signed bundle, inspect it without transmitting data:

```sh
python3 Suzzme/Validation/release-preflight.py \
  --app /absolute/path/to/Suzzme.app --platform macos \
  --output /private/tmp/suzzme-mac-release-audit.json --require-release
codesign --verify --deep --strict /absolute/path/to/Suzzme.app
```

For iOS use `--platform ios` and the exported device app, not a Simulator bundle. Audit exit 2 means a build/configuration gate is missing. Exit 0 does **not** establish runtime, live-provider, hardware or release acceptance. The output always keeps `releaseReady` false.

## macOS archive and export

Choose Developer ID distribution or the Mac App Store with the owner. The following Developer ID route requires a valid distribution identity, correct entitlements/profiles and explicit authorization for signing. No automatic provisioning/account changes are included:

```sh
xcodebuild -project Suzzme/Suzzme.xcodeproj -scheme Suzzme \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath /private/tmp/SuzzmeMac.xcarchive archive
xcodebuild -exportArchive -archivePath /private/tmp/SuzzmeMac.xcarchive \
  -exportOptionsPlist Suzzme/Release/ExportOptionsDeveloperID.plist \
  -exportPath /private/tmp/SuzzmeMacExport
```

Verify the exported app, nested helpers, Hardened Runtime, app-only Keychain group and provisioned shared broker group. Repeat live browser and physical voice tests on this exact build. The export plist names the inspected team but creates no identity or profile.

After explicit authorization to submit, use an existing locally stored `notarytool` Keychain profile with the owner's real name. Do not paste its credentials into chat or commands. Package the signed app, submit, inspect the notarization result, then staple the **same** app. Do not treat upload success as notarization success. [Apple notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

```sh
ditto -c -k --keepParent /absolute/export/Suzzme.app /private/tmp/Suzzme.zip
xcrun notarytool submit /private/tmp/Suzzme.zip --keychain-profile ACTUAL_PROFILE_NAME --wait
xcrun stapler staple /absolute/export/Suzzme.app
xcrun stapler validate /absolute/export/Suzzme.app
spctl --assess --type execute --verbose=4 /absolute/export/Suzzme.app
```

`ACTUAL_PROFILE_NAME` is an instruction placeholder, not a configured profile. A notarization failure must be resolved before distribution.

## Installed browser acceptance

First validate real app/helper signatures and provisioned broker entitlements. Prepare the manifest with the existing signature-checking helper:

```sh
python3 Suzzme/BrowserNativeHost/prepare-chrome-manifest.py \
  --app /absolute/installed/Suzzme.app --extension-id ACTUAL_EXTENSION_ID \
  --output /private/tmp/rehan.suzzme.browser_context.json
```

This only prepares a manifest. Installing it at `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/rehan.suzzme.browser_context.json`, registering the broker and pairing the exact published/approved extension are separate authorized steps. The manifest's absolute path must reference the installed app, not temporary DerivedData. Verify GitHub-page → authenticated host → signed broker → Presence → explicit approval → GitHub verification sheet; this must not grant provider access. [Chrome Native Messaging requirements](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging).

## iOS archive and local export

Provision both the app and Presence extension for the actual team and device/distribution route. Build a device archive only after signing prerequisites are configured:

```sh
xcodebuild -project Suzzme/Suzzme.xcodeproj -scheme Suzzme \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /private/tmp/SuzzmeIOS.xcarchive archive
xcodebuild -exportArchive -archivePath /private/tmp/SuzzmeIOS.xcarchive \
  -exportOptionsPlist Suzzme/Release/ExportOptionsAppStore.plist \
  -exportPath /private/tmp/SuzzmeIOSExport
```

The App Store export explicitly uses `destination=export`; it does not authorize upload. App Store Connect app registration, aggregate SDK privacy disclosures, export compliance, TestFlight upload, review and publication require owner participation. Do not claim device acceptance from a Simulator archive or an unsigned build.

## Installation, upgrade and removal gates

Use a dedicated test account/device and the final signed artifacts. Observe clean onboarding, permission denial/recovery, profile/settings persistence, authorized resource restoration, migration without lost memory, helper replacement, Chrome/Suzzme restarts and revocation. Confirm only one Presence panel. Test uninstall/reinstall separately: do not promise that moving the app to Trash deletes Keychain credentials, app data or a separately installed Native Messaging manifest. Exercise Suzzme's explicit disconnect/unpair controls before removal when desired; request approval before deleting user data. Record device/OS/build/signature/hash for every accepted gate.
