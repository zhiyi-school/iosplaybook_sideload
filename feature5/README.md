# Local Keyboard

A minimal iOS app plus custom keyboard extension for local testing.

The keyboard records only keys tapped inside this custom keyboard after the user enables it in iOS Settings. It does not capture the system keyboard, other keyboards, background input, passwords, or hidden/global keystrokes.

## Xcode Setup

1. Open `LocalKeyboard.xcodeproj`.
2. Select both targets and set your signing team.
3. Replace the example bundle IDs if needed:
   - `com.example.LocalKeyboard`
   - `com.example.LocalKeyboard.KeyboardExtension`
4. Register and enable the App Group on both targets:
   - `group.com.example.LocalKeyboard`
5. Run the app on a simulator or device.
6. Enable the keyboard in iOS Settings:
   - Settings > General > Keyboard > Keyboards > Add New Keyboard > Local Keyboard
   - Turn on Full Access so the extension can write to the shared App Group container.

Open the app again to view or clear stored events.

## Remote Input Server

The keyboard can poll a paired local server while the custom keyboard is visible. It only inserts queued text into the currently focused field after the user has enabled and selected this keyboard.

1. Start the local server. It creates a token automatically:

   ```sh
   python3 server/local_input_server.py
   ```

2. Open the app and change the Server URL if needed.
   - The default comes from `KeystrokeStore.defaultServerURL` in `LocalKeyboard/KeystrokeStore.swift`.
   - The field accepts `IP:PORT`, for example `10.132.0.13:8765`.
   - If you omit `http://`, the app adds it automatically.
   - Simulator example: `http://127.0.0.1:8765`
   - Device testing example: `http://192.168.1.20:8765`
3. The app pairs automatically.
   - The app calls `POST /pair` on the server.
   - It falls back to `GET /pair` for the original bundled test server.
   - The server returns its generated token.
   - The app saves that token into the shared App Group settings used by the keyboard extension.
   - Pairing runs when the app opens, when it returns to the foreground, and shortly after the server URL changes.
   - Re-pairing is allowed while the server is running.
4. Queue text from another terminal using the token printed by the server or shown in the app:

   ```sh
   curl -X POST http://127.0.0.1:8765/enqueue \
     -H "Content-Type: application/json" \
     -d '{"token":"SERVER_TOKEN","text":"hello from server"}'
   ```

5. Focus a text field on iOS, switch to Local Keyboard, and keep it visible. The extension polls `/next?token=SERVER_TOKEN` and inserts queued text with `textDocumentProxy.insertText`.

You can also provide your own server token with `--token YOUR_TOKEN`.

The keyboard does not accept arbitrary commands, does not run in the background, and does not type unless the custom keyboard is active in a focused text field.
