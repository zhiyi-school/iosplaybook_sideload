# KeychainTestApp

KeychainTestApp is a minimal SwiftUI iOS proof-of-concept for controlled testing of native Keychain retrieval through `SecItemCopyMatching()`.

Use this project only on apps and devices you own or are authorized to test.

## What It Does

The app stores one predictable generic-password Keychain item:

```text
service = "com.example.KeychainTestApp"
account = "test-user"
class   = kSecClassGenericPassword
```

All native Security framework calls live in `KeychainTestApp/KeychainManager.swift`:

- `SecItemAdd()`
- `SecItemCopyMatching()`
- `SecItemDelete()`

The main screen includes manual Save, Read, and Delete buttons plus **Run Keychain Test**, which runs a deterministic delete-save-read-compare flow using `TEST_KEYCHAIN_SECRET_12345`.

## Quick Start

Open `KeychainTestApp.xcodeproj` in Xcode, select your development team under **Signing & Capabilities**, choose a physical iPhone, then build and run.

Tap **Run Keychain Test**. A successful run shows:

```text
RESULT: PASS
```

## Docs

- [IPA Archive and Frida Gadget Notes](docs/ipa-repackaging.md)
- [Frida Keychain Hooking](docs/frida-hooking.md)

## Runtime Scenario

```text
Clean IPA
    -> Install and launch
    -> Run Keychain Test
    -> Verify normal Keychain operation

Instrumented IPA containing Frida Gadget
    -> Install and launch
    -> Attach Frida hook
    -> Run Keychain Test
    -> Observe SecItemCopyMatching() at runtime
```

The app prints console markers around each Keychain call, but it does not print the secret value to the console.
