# BiometricBypassDemo

BiometricBypassDemo is a small iOS SwiftUI app that demonstrates the biometric-bypass risk described by OWASP MASTG-TECH-0135.

The demo models a banking transfer flow:

1. The user is already signed in.
2. The user enters a recipient and transfer amount.
3. The app asks for Face ID or Touch ID.
4. The app submits the transfer after local biometric success.

The weakness is that the app treats the local `LAContext.evaluatePolicy` callback as enough proof to authorize the transfer. A runtime hook can forge that callback, causing the app to continue as if biometric authentication succeeded.

Use this project only on apps and devices you own or are authorized to test.

## What This Shows

This project shows why local biometric checks should not be the final authority for sensitive actions. Local app state can be modified at runtime, especially in debug builds and research setups.

The secure design is to bind the sensitive action to a protected cryptographic operation, such as a Keychain/Secure Enclave backed challenge or transaction signature. The server should verify that proof before accepting the operation.

## Project Layout

```text
BiometricBypassDemo/                iOS SwiftUI demo app
scripts/force-biometric-success.js    Frida hook that forces biometric success
ThirdParty/Frida/FridaGadget.dylib    Frida Gadget binary for jailed-iOS flows
ThirdParty/Frida/FridaGadget.config   Gadget listener config
docs/                              Technical setup and troubleshooting notes
```

Frida Gadget is not linked into the main Xcode target by default. The repository includes a Gadget binary and config for the optional jailed-iOS and IPA workflows. The checked-in Gadget copy is for Frida `17.9.10`; your local `frida-tools` version should match it, or you should replace the dylib with the matching Gadget release.

## Obtaining Frida Gadget

This repo currently includes `ThirdParty/Frida/FridaGadget.dylib`, which is intended to match Frida `17.9.10`.

Check your installed Frida version:

```sh
python3 -m pip install --user frida-tools
frida --version
```

If your local Frida version is not `17.9.10`, download the matching Gadget asset from the Frida release with the same version as your `frida --version` output:

```text
frida-gadget-VERSION-ios-universal.dylib.xz
```

Decompress it, then replace the repo copy:

```sh
mkdir -p ThirdParty/Frida
cp path/to/gadget-ios.dylib ThirdParty/Frida/FridaGadget.dylib
```

The Frida CLI and Gadget dylib should be kept on the same version. Version mismatches can cause attach failures, crashes, or confusing connection errors on jailed iOS.

## Quick Start

Open `BiometricBypassDemo.xcodeproj` in Xcode, select your development team, and run the app on a device with Face ID or Touch ID enrolled.

To observe the normal behavior, tap **Send Transfer** and cancel the biometric prompt. The transfer should be blocked.

To reproduce the runtime bypass in a controlled test setup, see:

- [Frida on Jailed iOS](docs/frida-jailed-ios.md)
- [IPA Repackaging Notes](docs/ipa-repackaging.md)
- [Troubleshooting](docs/troubleshooting.md)

## Production Fix

Do not authorize sensitive operations from a local biometric Boolean. Use Keychain/Secure Enclave access control and have the server verify a challenge response or transaction signature bound to the operation details.
