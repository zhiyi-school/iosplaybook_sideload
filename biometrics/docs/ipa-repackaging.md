# IPA Repackaging Notes

These notes describe the optional IPA-based workflow. Use this only for an app you own or are authorized to test.

On an unjailbroken iPhone, the IPA must be decrypted or non-encrypted, patched to load Frida Gadget, and re-signed with a development provisioning profile that includes your device.

## Unpack the IPA

```sh
IPA=BiometricBypassDemo.ipa
WORK=patched-ipa
rm -rf "$WORK"
mkdir "$WORK"
unzip -q "$IPA" -d "$WORK"
APP_PATH=$(find "$WORK/Payload" -maxdepth 1 -name "*.app" -print -quit)
APP_BIN="$APP_PATH/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Info.plist")"
```

## Add Frida Gadget

```sh
mkdir -p "$APP_PATH/Frameworks"
cp ~/.cache/frida/gadget-ios.dylib "$APP_PATH/Frameworks/FridaGadget.dylib"
cp ThirdParty/Frida/FridaGadget.config "$APP_PATH/Frameworks/FridaGadget.config"
```

Patch the app binary to load Gadget. If `insert_dylib` is not installed:

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

Patch the binary:

```sh
insert_dylib --strip-codesig --inplace "@executable_path/Frameworks/FridaGadget.dylib" "$APP_BIN"
```

If you already have `optool`, the equivalent command is:

```sh
optool install -c load -p "@executable_path/Frameworks/FridaGadget.dylib" -t "$APP_BIN"
```

## Choose a Development Profile

The profile does not need to come from the original IPA. For repackaging, you normally replace the original `embedded.mobileprovision` with your own development profile.

List local profiles:

```sh
find ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles -name "*.mobileprovision" -print
```

Inspect candidates:

```sh
for PROFILE in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
  echo "=== $PROFILE"
  strings "$PROFILE" | egrep -A2 '<key>(Name|UUID|TeamIdentifier|application-identifier|get-task-allow|ExpirationDate|ProvisionedDevices)</key>'
done
```

Choose a profile where:

1. `application-identifier` ends with your bundle ID.
2. `TeamIdentifier` matches your Apple team.
3. `ProvisionedDevices` includes your iPhone UDID.
4. `get-task-allow` is true.

Set the values from your profile:

```sh
TEAM_ID=YOUR_TEAM_ID
BUNDLE_ID=com.yourname.BiometricBypassDemo
PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/YOUR_PROFILE.mobileprovision"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_PATH/Info.plist"
cp "$PROFILE" "$APP_PATH/embedded.mobileprovision"
```

## Create Matching Entitlements

```sh
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

Do not leave placeholder bundle IDs such as `com.yourname.BiometricBypassDemo`, or installation will fail with a provisioning profile error.

## Re-sign the App

Find your signing identity:

```sh
security find-identity -v -p codesigning
```

Use the long hexadecimal identity hash, not the display name. This avoids ambiguity if Keychain contains duplicate certificates with the same label.

```sh
IDENTITY=YOUR_CODESIGN_IDENTITY_HASH

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

Verify:

```sh
otool -L "$APP_BIN" | grep FridaGadget
codesign -d --entitlements :- "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
```

## Repackage and Install

```sh
(cd "$WORK" && zip -qry "../BiometricBypassDemo-frida.ipa" Payload)
```

`devicectl` installs the `.app` bundle, so point it at the app inside the unpacked IPA working directory:

```sh
xcrun xctrace list devices
DEVICE_ID=YOUR_IPHONE_UDID
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
```

If you only have the repackaged IPA later:

```sh
IPA=BiometricBypassDemo-frida.ipa
INSTALL_WORK=install-ipa
rm -rf "$INSTALL_WORK"
mkdir "$INSTALL_WORK"
unzip -q "$IPA" -d "$INSTALL_WORK"
APP_PATH=$(find "$INSTALL_WORK/Payload" -maxdepth 1 -name "*.app" -print -quit)
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
```

Launch the app, then attach to Gadget:

```sh
frida -U -n Gadget -l scripts/force-biometric-success.js
```

If Frida lists the Gadget identifier instead of the process name:

```sh
frida -U -N re.frida.Gadget -l scripts/force-biometric-success.js
```

App Store IPAs are usually encrypted and cannot be patched directly with this workflow.
