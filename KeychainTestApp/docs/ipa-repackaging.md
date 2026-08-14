# IPA Archive and Frida Gadget Notes

These notes describe how to produce a clean `KeychainTestApp` IPA and an instrumented IPA that embeds Frida Gadget. Use this only for an app and device you own or are authorized to test.

The app source does not include Frida Gadget. The Gadget workflow below modifies a built IPA after export, then re-signs it with your own development identity and provisioning profile.

App Store IPAs are usually encrypted and cannot be patched directly with this workflow.

## Prerequisites

Install Xcode and connect your iPhone by USB. Trust the computer on the device.

Install Frida tools:

```sh
python3 -m pip install --user frida-tools
frida --version
frida-ps -U
```

Install `insert_dylib` if you do not already have it:

```sh
git clone https://github.com/Tyilo/insert_dylib.git /tmp/insert_dylib
xcodebuild \
  -project /tmp/insert_dylib/insert_dylib.xcodeproj \
  -scheme insert_dylib \
  -configuration Release \
  SYMROOT=/tmp/insert_dylib/build \
  build

mkdir -p ~/bin
cp /tmp/insert_dylib/build/Release/insert_dylib ~/bin/
export PATH="$HOME/bin:$PATH"
```

Find the values you need:

```sh
security find-identity -v -p codesigning
xcrun xctrace list devices
```

Use the long codesigning hash, not the display name. That avoids ambiguous identity errors when Keychain has duplicate Apple Development certificates.

## Archive and Export the Clean IPA

Run these commands from the project folder and replace the variables with your own values:

```sh
cd /Users/user/playbook/iosplaybook_sideload/KeychainTestApp

TEAM_ID=YOUR_TEAM_ID
DEVICE_ID=YOUR_IPHONE_UDID
BUNDLE_ID=com.yourname.KeychainTestApp
ARCHIVE_PATH=build/KeychainTestApp.xcarchive
EXPORT_DIR=dist-clean
OUT_DIR=dist
```

Archive the app:

```sh
rm -rf build "$EXPORT_DIR" "$OUT_DIR"
mkdir -p "$OUT_DIR"

xcodebuild \
  -project KeychainTestApp.xcodeproj \
  -scheme KeychainTestApp \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  clean archive
```

Create an export options plist:

```sh
EXPORT_OPTIONS=exportOptions.plist
rm -f "$EXPORT_OPTIONS"
plutil -create xml1 "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :method string development" "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :signingStyle string automatic" "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :destination string export" "$EXPORT_OPTIONS"
```

Export the clean IPA:

```sh
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates

cp "$EXPORT_DIR/KeychainTestApp.ipa" "$OUT_DIR/KeychainTestApp-clean.ipa"
```

Install the clean app for a baseline run:

```sh
CLEAN_INSTALL_WORK=install-clean
rm -rf "$CLEAN_INSTALL_WORK"
mkdir "$CLEAN_INSTALL_WORK"
unzip -q "$OUT_DIR/KeychainTestApp-clean.ipa" -d "$CLEAN_INSTALL_WORK"
CLEAN_APP_PATH=$(find "$CLEAN_INSTALL_WORK/Payload" -maxdepth 1 -name "*.app" -print -quit)
xcrun devicectl device install app --device "$DEVICE_ID" "$CLEAN_APP_PATH"
```

Launch the app and tap **Run Keychain Test**. A normal successful run should display `RESULT: PASS`.

## Prepare Frida Gadget

The Frida CLI and Gadget dylib should be the same version.

If you already have the biometrics demo assets in this repo, you can reuse them:

```sh
GADGET_DYLIB=../biometrics/ThirdParty/Frida/FridaGadget.dylib
GADGET_CONFIG=../biometrics/ThirdParty/Frida/FridaGadget.config
```

Otherwise, download the matching iOS Gadget release asset:

```text
frida-gadget-VERSION-ios-universal.dylib.xz
```

Decompress it and place it in this project:

```sh
mkdir -p ThirdParty/Frida
cp path/to/gadget-ios.dylib ThirdParty/Frida/FridaGadget.dylib
```

Create `ThirdParty/Frida/FridaGadget.config` with:

```json
{
  "interaction": {
    "type": "listen",
    "address": "127.0.0.1",
    "port": 27042,
    "on_load": "resume"
  },
  "code_signing": "required"
}
```

Then use these paths:

```sh
GADGET_DYLIB=ThirdParty/Frida/FridaGadget.dylib
GADGET_CONFIG=ThirdParty/Frida/FridaGadget.config
```

The `code_signing` value is important on jailed iOS. Without it, a patched app may terminate immediately with `SIGTRAP` (`signal 5`) when Gadget starts.

## Patch the IPA with Frida Gadget

Use the clean IPA exported above:

```sh
IPA=dist/KeychainTestApp-clean.ipa
WORK=patched-ipa
OUT_IPA=dist/KeychainTestApp-frida.ipa
IDENTITY=YOUR_CODESIGN_IDENTITY_HASH
```

Unpack it and locate the app binary:

```sh
rm -rf "$WORK" "$OUT_IPA"
mkdir -p "$WORK"
unzip -q "$IPA" -d "$WORK"

APP_PATH=$(find "$WORK/Payload" -maxdepth 1 -name "*.app" -print -quit)
APP_BIN="$APP_PATH/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Info.plist")"
```

Add Frida Gadget to the app bundle:

```sh
mkdir -p "$APP_PATH/Frameworks"
cp "$GADGET_DYLIB" "$APP_PATH/Frameworks/FridaGadget.dylib"
cp "$GADGET_CONFIG" "$APP_PATH/Frameworks/FridaGadget.config"

insert_dylib --strip-codesig --inplace "@executable_path/Frameworks/FridaGadget.dylib" "$APP_BIN"
```

If you already have `optool`, the equivalent binary patch command is:

```sh
optool install -c load -p "@executable_path/Frameworks/FridaGadget.dylib" -t "$APP_BIN"
```

## Choose a Development Profile

The profile does not need to come from the original IPA. For repackaging, you normally replace the original `embedded.mobileprovision` with your own development profile.

If needed, make Xcode create or refresh a development profile for this bundle ID by building once with automatic signing:

```sh
xcodebuild \
  -project KeychainTestApp.xcodeproj \
  -scheme KeychainTestApp \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  build
```

Inspect local profiles:

```sh
for PROFILE in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
  echo "=== $PROFILE"
  security cms -D -i "$PROFILE" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null
  security cms -D -i "$PROFILE" 2>/dev/null | plutil -extract Entitlements.get-task-allow raw -o - - 2>/dev/null
  security cms -D -i "$PROFILE" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null
  security cms -D -i "$PROFILE" 2>/dev/null | plutil -extract ProvisionedDevices.0 raw -o - - 2>/dev/null
  echo
done
```

Choose a profile where:

1. `application-identifier` ends with your bundle ID.
2. `TeamIdentifier` matches your Apple team.
3. `ProvisionedDevices` includes your iPhone UDID.
4. `get-task-allow` is true.

Set `PROFILE` to the matching `.mobileprovision` file:

```sh
PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/YOUR_PROFILE.mobileprovision"
```

Use the same `TEAM_ID` and `BUNDLE_ID` for the clean and Frida IPAs so both variants behave like the same app:

```sh
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_PATH/Info.plist"
cp "$PROFILE" "$APP_PATH/embedded.mobileprovision"
```

## Create Matching Entitlements

```sh
rm -f debug-entitlements.plist
plutil -create xml1 debug-entitlements.plist
/usr/libexec/PlistBuddy -c "Add :application-identifier string $TEAM_ID.$BUNDLE_ID" debug-entitlements.plist
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" debug-entitlements.plist
/usr/libexec/PlistBuddy -c "Add :get-task-allow bool true" debug-entitlements.plist
```

The values must line up exactly:

```text
Info.plist CFBundleIdentifier
  must equal
embedded.mobileprovision application-identifier suffix
  and codesign entitlements must equal
TEAM_ID + "." + BUNDLE_ID
```

Do not leave placeholder bundle IDs such as `com.yourname.KeychainTestApp`, or installation will fail with a provisioning profile error.

## Re-sign the App

Sign nested content first, then the app bundle:

```sh
find "$APP_PATH" -maxdepth 3 -type d -name "*.framework" -print0 | while IFS= read -r -d '' FRAMEWORK; do
  codesign -f -s "$IDENTITY" "$FRAMEWORK"
done

find "$APP_PATH" -maxdepth 4 -type f -name "*.dylib" -print0 | while IFS= read -r -d '' ITEM; do
  codesign -f -s "$IDENTITY" "$ITEM"
done

find "$APP_PATH" -maxdepth 4 -type d -name "*.appex" -print0 | while IFS= read -r -d '' EXTENSION; do
  codesign -f -s "$IDENTITY" "$EXTENSION"
done

codesign -f -s "$IDENTITY" --entitlements debug-entitlements.plist "$APP_PATH"
```

Verify the patched app:

```sh
otool -L "$APP_BIN" | grep FridaGadget
codesign -d --entitlements :- "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
```

## Repackage and Install the Instrumented App

```sh
(cd "$WORK" && zip -qry "../$OUT_IPA" Payload)
```

`devicectl` installs the `.app` bundle, so point it at the app inside the unpacked IPA working directory:

```sh
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
```

If you only have the repackaged IPA later:

```sh
INSTALL_WORK=install-frida
rm -rf "$INSTALL_WORK"
mkdir "$INSTALL_WORK"
unzip -q "$OUT_IPA" -d "$INSTALL_WORK"
APP_PATH=$(find "$INSTALL_WORK/Payload" -maxdepth 1 -name "*.app" -print -quit)
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
```

Launch the app, then attach to Gadget:

```sh
frida-ps -Uai | grep -i "gadget\|keychain"
frida -U -n Gadget -l scripts/keychain-observe.js
```

If Frida lists the Gadget identifier instead of the process name:

```sh
frida -U -N re.frida.Gadget -l scripts/keychain-observe.js
```

With Frida attached, tap **Run Keychain Test** and observe the app calling `SecItemCopyMatching()`. The app should behave the same as the clean IPA and display `RESULT: PASS`.

For details on the included hook script and expected output, see [Frida Keychain Hooking](frida-hooking.md).

If the app installs but closes immediately with `signal 5`, make sure the copied `FridaGadget.config` includes `"code_signing": "required"`, then repeat the patch, sign, package, and install steps.
