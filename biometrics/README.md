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
BiometricBypassDemo/              iOS SwiftUI demo app
scripts/force-biometric-success.js  Frida hook that forces biometric success
ThirdParty/Frida/FridaGadget.config Gadget listener config used by optional flows
docs/                            Technical setup and troubleshooting notes
```

Frida Gadget is not linked into the main Xcode target by default. The repository keeps a Gadget config for the optional jailed-iOS and IPA workflows, but the actual Gadget dylib should be downloaded locally and is ignored by Git.

## Quick Start

Open `BiometricBypassDemo.xcodeproj` in Xcode, select your development team, and run the app on a device with Face ID or Touch ID enrolled.

To observe the normal behavior, tap **Send Transfer** and cancel the biometric prompt. The transfer should be blocked.

To reproduce the runtime bypass in a controlled test setup, see:

- [Frida on Jailed iOS](docs/frida-jailed-ios.md)
- [IPA Repackaging Notes](docs/ipa-repackaging.md)
- [Troubleshooting](docs/troubleshooting.md)

## Production Fix

Do not authorize sensitive operations from a local biometric Boolean. Use Keychain/Secure Enclave access control and have the server verify a challenge response or transaction signature bound to the operation details.
