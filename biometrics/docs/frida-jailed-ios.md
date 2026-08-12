# Frida on Jailed iOS

These notes explain the source-build Frida flow for a non-jailbroken iPhone. Use this only with an app and device you own or are authorized to test.

## Prerequisites

Install Xcode, connect your iPhone by USB, trust the computer on the device, and enroll Face ID or Touch ID.

Install Frida tools:

```sh
python3 -m pip install --user frida-tools
```

Confirm Frida can see the device:

```sh
frida --version
frida-ps -U
```

Find your Apple Team ID and device UDID:

```sh
security find-identity -v -p codesigning
xcrun xctrace list devices
```

The Team ID is the value in parentheses at the end of the Apple Development identity:

```text
1) ABCDEF1234567890 "Apple Development: Your Name (TEAMID1234)"
```

The device UDID appears in the device list:

```text
Your iPhone (26.0) (00008120-0001110834E1A01E)
```

## Build a Debug App

Frida needs the app to be debuggable on a non-jailbroken device. The important entitlement is:

```xml
<key>get-task-allow</key>
<true/>
```

A normal Xcode Debug build signed with a development profile usually includes this automatically. This project also includes `BiometricBypassDemo/Debug.entitlements`.

Example command-line build:

```sh
TEAM_ID=YOUR_TEAM_ID
DEVICE_ID=YOUR_IPHONE_UDID
BUNDLE_ID=com.yourname.BiometricBypassDemo

xcodebuild \
  -project BiometricBypassDemo.xcodeproj \
  -scheme BiometricBypassDemo \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_ENTITLEMENTS=BiometricBypassDemo/Debug.entitlements \
  CODE_SIGN_STYLE=Automatic \
  build
```

Verify the built app:

```sh
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Debug-iphoneos/BiometricBypassDemo.app" -print -quit)
codesign -d --entitlements :- "$APP_PATH"
```

Look for `get-task-allow` set to `true`.

## Run the Hook

Open the app on the iPhone and keep it in the foreground. Confirm the process is visible:

```sh
frida-ps -U | grep -i biometric
```

Attach with the exact process name:

```sh
frida -U -n "Biometric Bypass Demo" -l scripts/force-biometric-success.js
```

You can also attach to the frontmost app:

```sh
frida -U -F -l scripts/force-biometric-success.js
```

With Frida attached, tap **Send Transfer**. The script replaces `LAContext.evaluatePolicy:localizedReason:reply:` and calls the completion block with success.

## When Frida Requires Gadget

On jailed iOS, direct attach or spawn may fail with a message like:

```text
need Gadget to attach on jailed iOS
```

Install the matching iOS Frida Gadget dylib in Frida's local cache. The Gadget version must match `frida --version`.

```sh
FRIDA_VERSION=$(frida --version)
mkdir -p ~/.cache/frida
```

Download the matching Frida release asset:

```text
frida-gadget-${FRIDA_VERSION}-ios-universal.dylib.xz
```

Decompress it and save it as:

```text
~/.cache/frida/gadget-ios.dylib
```

If automatic Gadget injection crashes, embed Gadget into the app instead:

```sh
mkdir -p ThirdParty/Frida
cp ~/.cache/frida/gadget-ios.dylib ThirdParty/Frida/FridaGadget.dylib
```

Use this config at `ThirdParty/Frida/FridaGadget.config`:

```json
{
  "interaction": {
    "type": "listen",
    "address": "127.0.0.1",
    "port": 27042,
    "on_load": "resume"
  }
}
```

Then in Xcode:

1. Drag `ThirdParty/Frida/FridaGadget.dylib` and `ThirdParty/Frida/FridaGadget.config` into the project navigator.
2. Open the `BiometricBypassDemo` target.
3. In **Build Phases** > **Link Binary With Libraries**, add `FridaGadget.dylib`.
4. Add a **Copy Files** build phase, set **Destination** to **Frameworks**, add `FridaGadget.dylib`, and enable **Code Sign On Copy**.
5. Add `FridaGadget.config` to **Copy Bundle Resources**.
6. Build and run the app from Xcode in Debug.

Verify the built app:

```sh
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Debug-iphoneos/BiometricBypassDemo.app" -print -quit)
find "$APP_PATH" -name "FridaGadget*"
otool -L "$APP_PATH/BiometricBypassDemo" | grep FridaGadget
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
```

Attach to Gadget:

```sh
frida-ps -Uai | grep -i "gadget\|biometric"
frida -U -n Gadget -l scripts/force-biometric-success.js
```

If Frida lists the Gadget identifier instead of the process name:

```sh
frida -U -N re.frida.Gadget -l scripts/force-biometric-success.js
```
