# Troubleshooting

## `unable to find process with name`

The app is installed but not running, or the process name is different from the bundle name.

Check installed apps and running processes:

```sh
frida-ps -Uai | grep -i biometric
frida-ps -U | grep -i biometric
```

Open the app on the iPhone and keep it in the foreground before attaching.

## `need Gadget to attach on jailed iOS`

On a non-jailbroken iPhone, Frida may require the matching iOS Frida Gadget dylib.

The version must match:

```sh
frida --version
```

Download the matching `frida-gadget-VERSION-ios-universal.dylib.xz`, decompress it, and save it as:

```text
~/.cache/frida/gadget-ios.dylib
```

## `Failed to attach: connection closed`

The process was visible, but iOS closed the attach session.

Check that the app is a Debug build signed with `get-task-allow`:

```sh
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Debug-iphoneos/BiometricBypassDemo.app" -print -quit)
codesign -d --entitlements :- "$APP_PATH"
```

If `get-task-allow` is present and attach still fails, use the Gadget flow in [Frida on Jailed iOS](frida-jailed-ios.md).

## Gadget App Closes Immediately

On jailed iOS, Gadget may be killed at launch if it tries to use code-patching features before a debugger has relaxed code-signing restrictions.

You can temporarily add `code_signing` to `FridaGadget.config` to confirm that the bundle and signature are otherwise valid:

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

That mode may stop the immediate crash, but it disables code-patching APIs. The biometric hook in `scripts/force-biometric-success.js` needs code patching, so it will not work in this mode.

For this hook on a non-jailbroken phone, launch the app under Xcode/LLDB debugging first so the relaxed code-signing state is active, then attach Frida.

## Provisioning Profile Install Error

An install failure like this means the signature, entitlements, bundle ID, and provisioning profile do not match:

```text
A valid provisioning profile for this executable was not found.
```

Check these values:

1. `Info.plist` `CFBundleIdentifier`
2. `embedded.mobileprovision` `application-identifier`
3. codesign entitlement `application-identifier`
4. codesign entitlement `get-task-allow`
5. `ProvisionedDevices` includes your iPhone UDID

For repackaging, the profile can be your own development profile. It does not have to come from the original IPA.

## Ambiguous Codesign Identity

If `codesign` says the identity is ambiguous, Keychain has multiple certificates with the same display name.

Use the hash from:

```sh
security find-identity -v -p codesigning
```

Example:

```sh
IDENTITY=2452128391D900EE9EFF605B28ACA662FD090769
codesign -f -s "$IDENTITY" --entitlements debug-entitlements.plist "$APP_PATH"
```

## Untrusted Developer

Personal or development-signed apps may need to be trusted on the device before they launch. iOS controls this trust state on the phone. Reinstalling, changing profiles, changing certificates, or deleting trust state can cause the prompt to appear again even if the visible signing name looks the same.
