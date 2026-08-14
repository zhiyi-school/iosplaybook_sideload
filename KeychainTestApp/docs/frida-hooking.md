# Frida Keychain Hooking

These notes show how to observe `KeychainTestApp` calling native Keychain APIs at runtime. Use this only on apps and devices you own or are authorized to test.

The included script focuses on `SecItemCopyMatching()`, plus lightweight status logging for `SecItemAdd()` and `SecItemDelete()`. It does not print the secret value returned from the Keychain.

## Prerequisites

Install Frida tools and confirm the device is visible:

```sh
python3 -m pip install --user frida-tools
frida --version
frida-ps -U
```

Build or install one of these variants:

- Clean debug build signed with `get-task-allow`.
- Instrumented IPA that embeds Frida Gadget. See [IPA Archive and Frida Gadget Notes](ipa-repackaging.md).

## Attach to the Gadget Build

Launch `Keychain Test` on the iPhone and keep it in the foreground.

Find the visible process or Gadget endpoint:

```sh
frida-ps -Uai | grep -i "gadget\|keychain"
```

Attach to Gadget with the included script:

```sh
cd /Users/user/playbook/iosplaybook_sideload/KeychainTestApp
frida -U -n Gadget -l scripts/keychain-observe.js
```

If Frida lists the Gadget identifier instead of the process name:

```sh
frida -U -N re.frida.Gadget -l scripts/keychain-observe.js
```

With Frida attached, tap **Run Keychain Test** in the app.

What this hooks: `scripts/keychain-observe.js` watches the app's Keychain control flow. It hooks `SecItemDelete()` when the test clears the old item, `SecItemAdd()` when the test saves the fixed value, and `SecItemCopyMatching()` when the app reads the value back. The script logs OSStatus return codes and returned data length, but not the secret value.

## Commands Inside Frida

If Frida is already open at a prompt like this:

```text
[Remote::Gadget ]->
```

load the hook script without restarting Frida:

```js
%load scripts/keychain-observe.js
```

If you are not in the `KeychainTestApp` folder, use the absolute path:

```js
%load /Users/user/playbook/iosplaybook_sideload/KeychainTestApp/scripts/keychain-observe.js
```

After editing the script, reload it:

```js
%reload
```

What this hooks: loading or reloading `scripts/keychain-observe.js` installs the same observer hooks as the startup command. Use this when Frida is already attached and you want to apply the hook script without closing the session.

To hook only `SecItemCopyMatching()` manually from the Frida prompt, paste this snippet:

```js
const securityModule = Process.getModuleByName("Security");
const secItemCopyMatching = securityModule.getExportByName("SecItemCopyMatching");

Interceptor.attach(secItemCopyMatching, {
  onEnter(args) {
    this.resultPointer = args[1];
    console.log("[ManualHook] SecItemCopyMatching called");
    console.log("[ManualHook] query=" + args[0] + " result=" + args[1]);
  },
  onLeave(retval) {
    console.log("[ManualHook] SecItemCopyMatching returned: " + retval.toInt32());
  }
});
```

Then tap **Run Keychain Test** in the app. You should see the manual hook log when the read operation calls `SecItemCopyMatching()`.

What this hooks: `SecItemCopyMatching()` is the native Security framework read API. In this PoC, a successful return code means the app retrieved the generic-password item from the Keychain. The `result` argument points to the returned object, which is sensitive because it can contain the secret data after the call returns.

To add quick manual status hooks for the other two Keychain operations:

```js
Interceptor.attach(securityModule.getExportByName("SecItemAdd"), {
  onEnter(args) {
    console.log("[ManualHook] SecItemAdd called");
  },
  onLeave(retval) {
    console.log("[ManualHook] SecItemAdd returned: " + retval.toInt32());
  }
});

Interceptor.attach(securityModule.getExportByName("SecItemDelete"), {
  onEnter(args) {
    console.log("[ManualHook] SecItemDelete called");
  },
  onLeave(retval) {
    console.log("[ManualHook] SecItemDelete returned: " + retval.toInt32());
  }
});
```

These manual hooks observe calls and return codes only. They do not print the Keychain secret value.

What this hooks: `SecItemAdd()` is the native API used to create the Keychain item, and `SecItemDelete()` is used to remove it. These are useful companion hooks because they prove the full automated test sequence happened before the read hook fires.

## Dump Returned Data

For this controlled PoC, you can also prove what data is returned from the Keychain by using the explicit dumper script. This prints sensitive data and should only be used against `KeychainTestApp` on your own authorized test device.

Use a fresh Frida session so the import slot is not already wrapped by another script:

```sh
cd /Users/user/playbook/iosplaybook_sideload/KeychainTestApp
frida -U -n Gadget -l scripts/keychain-dump.js
```

What this hooks: `scripts/keychain-dump.js` wraps this app's imported `SecItemCopyMatching()` function pointer and inspects the returned `CFData` after a successful read. This is the sensitive point in the flow: the Keychain has already decrypted or released the item to the app, so runtime instrumentation can read the bytes in process memory.

Then tap **Run Keychain Test**. Expected output includes:

```text
[KeychainDump] SecItemCopyMatching returned: 0
[KeychainDump] Returned CFData length: 26 bytes
[KeychainDump] UTF-8 value: TEST_KEYCHAIN_SECRET_12345
```

The normal `scripts/keychain-observe.js` script avoids printing this value and is better for routine demonstrations where you only need to prove that retrieval happened.

## Attach to a Clean Debug Build

If the app was installed as a normal debuggable development build, direct attach may work:

```sh
cd /Users/user/playbook/iosplaybook_sideload/KeychainTestApp
frida -U -n KeychainTestApp -l scripts/keychain-observe.js
```

You can also attach to the frontmost app:

```sh
frida -U -F -l scripts/keychain-observe.js
```

On jailed iOS, direct attach can fail with a message saying Gadget is required. In that case, use the instrumented IPA workflow.

What this hooks: the clean debug build uses the same `scripts/keychain-observe.js` targets as the Gadget build. The difference is only the attach method: direct attach depends on the app being debuggable, while the Gadget build hosts Frida from inside the app process.

## Expected Output

When you tap **Run Keychain Test**, the app performs:

1. `SecItemDelete()`
2. `SecItemAdd()`
3. `SecItemCopyMatching()`

The Frida console should show output similar to:

```text
[KeychainHook] SecItemDelete(query=0x...)
[KeychainHook] SecItemDelete returned: 0
[KeychainHook] SecItemAdd(query=0x..., result=0x0)
[KeychainHook] SecItemAdd returned: 0
[KeychainHook] SecItemCopyMatching(query=0x..., result=0x...)
[KeychainHook] SecItemCopyMatching returned: 0
[KeychainHook] SecItemCopyMatching returned CFData length: 26 bytes
```

The iOS app should show:

```text
RESULT: PASS
```

## Troubleshooting

If the app closes immediately after launch, confirm `FridaGadget.config` includes:

```json
{
  "code_signing": "required"
}
```

If Frida cannot find `Gadget`, run:

```sh
frida-ps -Uai | grep -i "gadget\|keychain"
```

Then use the exact process name or identifier shown by Frida.

If the script reports a JavaScript API error such as `Module.findExportByName is not a function`, update to the current `scripts/keychain-observe.js`. The script uses compatibility export lookup for Frida versions where `Module.findExportByName()` is no longer available.

If the script prints `Hooked SecItemCopyMatching` but tapping **Run Keychain Test** prints nothing else, first confirm the prompt is attached to the app you are tapping:

```js
Process.enumerateModules()[0].path
```

The path should include `KeychainTestApp.app/KeychainTestApp`. If it does and calls still do not appear, update to the current `scripts/keychain-observe.js`; it hooks all matching Security exports and also wraps this app's imported Keychain function pointer slots. Restarting Frida is cleaner than `%reload` for this version:

```sh
frida -U -n Gadget -l scripts/keychain-observe.js
```

The import-slot fallback prints lines with `KeychainHook:Slot`, such as:

```text
[KeychainHook:Slot] SecItemCopyMatching(query=0x..., result=0x...)
[KeychainHook:Slot] SecItemCopyMatching returned: 0
```

If installation fails, confirm the app and `FridaGadget.dylib` were signed with a development identity and that the embedded provisioning profile includes your iPhone UDID.
