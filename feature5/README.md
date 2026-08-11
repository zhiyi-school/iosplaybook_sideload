# Local Keyboard

Minimal iOS app with a custom keyboard extension for local testing.

The keyboard only handles input that goes through this custom keyboard after the user enables it in iOS Settings. It does not capture the system keyboard, other keyboards, background input, password fields, hidden input, or global keystrokes.

## What Is Here

- `LocalKeyboard/`: SwiftUI container app.
- `KeyboardExtension/`: custom keyboard extension.
- `server/local_input_server.py`: local HTTP queue server.
- `ExportOptions.plist`: development IPA export settings.

The app stores keyboard events and server pairing settings in the shared App Group:

```text
group.com.example.LocalKeyboard
```

## Xcode Setup

1. Open `LocalKeyboard.xcodeproj`.
2. Select both targets and set your signing team.
3. Replace the example bundle IDs if needed:
   - `com.example.LocalKeyboard`
   - `com.example.LocalKeyboard.KeyboardExtension`
4. Register and enable the App Group on both targets:
   - `group.com.example.LocalKeyboard`
5. Run or archive the app.
6. Enable the keyboard on the device:
   - Settings > General > Keyboard > Keyboards > Add New Keyboard > Local Keyboard
   - Turn on Full Access so the extension can read the shared App Group settings and use network access.

## Remote Input Server

Start the local server:

```sh
python3 server/local_input_server.py
```

Defaults:

```text
host: 0.0.0.0
port: 8765
```

Useful options:

```sh
python3 server/local_input_server.py --host 0.0.0.0 --port 8765
python3 server/local_input_server.py --token YOUR_TOKEN
python3 server/local_input_server.py --enqueue-requires-token
```

The server prints a token and example curl command when it starts.

## App Server URL

The app has a `Server IP:Port` field in the Remote Input section.

Examples:

```text
10.132.0.29:8765
http://10.132.0.29:8765
http://127.0.0.1:8765
```

If you omit `http://`, the app adds it automatically. The source-code default is:

```swift
KeystrokeStore.defaultServerURL
```

The current default is in `LocalKeyboard/KeystrokeStore.swift`.

## Pairing Flow

The app pairs automatically when:

- the app opens,
- the app returns to the foreground,
- the server URL changes.

Pairing request:

```http
POST /pair
Content-Type: application/json

{"client":"LocalKeyboard"}
```

Pairing response:

```json
{"token":"SERVER_TOKEN"}
```

The app saves the token in App Group storage. The keyboard extension reads the same token before polling `/next`.

## Queue Input

Queue text with:

```sh
curl -X POST http://127.0.0.1:8765/enqueue \
  -H "Content-Type: application/json" \
  -d '{"token":"SERVER_TOKEN","text":"hello from server"}'
```

If the server was started without `--enqueue-requires-token`, the token is accepted but not required for enqueueing. The keyboard still needs the token for `/next`.

Queue return/newline as a separate input:

```sh
curl -X POST http://127.0.0.1:8765/enqueue \
  -H "Content-Type: application/json" \
  -d '{"token":"SERVER_TOKEN","text":"\n"}'
```

## Keyboard Behavior

The custom keyboard has:

- number row,
- QWERTY letter rows,
- space,
- delete,
- return.

Manual key taps are inserted into the active text field and logged in the app event list.

Remote input is only pulled while the custom keyboard is visible. The extension starts polling in `viewWillAppear`, stops in `viewWillDisappear`, and polls roughly every `0.8` seconds:

```text
GET /next?token=SERVER_TOKEN
```

Server empty response:

```json
{"id": null, "text": null}
```

Server queued response:

```json
{"id": 1, "text": "hello"}
```

The keyboard inserts the returned `text` with `textDocumentProxy.insertText(...)`.

## Server Endpoints

```text
GET  /health
POST /pair
POST /enqueue
GET  /next?token=SERVER_TOKEN
GET  /events
POST /events
GET  /snapshot
```

Debug snapshot:

```sh
curl http://127.0.0.1:8765/snapshot
```

This shows pairing state, queued items, delivered items, event count, request count, and unauthorized `/next` count.

## Build

Simulator compile check:

```sh
xcodebuild \
  -project LocalKeyboard.xcodeproj \
  -scheme LocalKeyboard \
  -sdk iphonesimulator \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Archive for iPhone:

```sh
xcodebuild \
  -project LocalKeyboard.xcodeproj \
  -scheme LocalKeyboard \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath /private/tmp/LocalKeyboard.xcarchive \
  archive
```

Export development IPA:

```sh
xcodebuild \
  -exportArchive \
  -archivePath /private/tmp/LocalKeyboard.xcarchive \
  -exportPath /private/tmp/LocalKeyboardIPA \
  -exportOptionsPlist ExportOptions.plist
```

Install on a connected iPhone:

```sh
xcrun devicectl list devices
xcrun devicectl device install app \
  --device DEVICE_IDENTIFIER \
  /private/tmp/LocalKeyboardIPA/LocalKeyboard.ipa
```

## Troubleshooting

`Pairing failed: App Transport Security...`

- The app and extension allow arbitrary HTTP loads for local testing in their `Info.plist` files.
- Rebuild and reinstall after changing plist values.

`Pairing rejected: not_found`

- The app reached a server, but the route was wrong.
- The field should be only `IP:PORT`, not `IP:PORT/pair`.
- Confirm the server supports `POST /pair`.

`Remote input rejected`

- The keyboard reached `/next`, but the response was not a valid `200` JSON response.
- Common causes: token mismatch, wrong server, `401 unauthorized`, or non-JSON response.
- Check:

```sh
curl "http://127.0.0.1:8765/next?token=SERVER_TOKEN"
curl http://127.0.0.1:8765/snapshot
```

Keyboard does not poll

- The custom keyboard must be visible.
- Full Access must be enabled.
- Polling stops when the keyboard disappears or another keyboard is selected.

Return/submit behavior

- The keyboard can insert `\n`, but iOS does not expose a universal submit/search/go API to custom keyboards.
- Some apps treat inserted newlines as spaces.
