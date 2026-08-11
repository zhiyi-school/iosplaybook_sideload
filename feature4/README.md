# Replay Consent Recorder

Replay Consent Recorder is a small iOS app that demonstrates screen recording with ReplayKit.

It supports two recording modes:

- **App screen recording**: records only this app using `RPScreenRecorder`.
- **Phone screen recording**: starts a ReplayKit broadcast upload extension so the device screen can be recorded while the app is in the background.

The app also saves screenshots every 5 seconds while signed in. Broadcast screenshots are captured by the extension during phone screen recording.

## Requirements

- macOS with Xcode installed
- iOS 17.0 or newer
- A physical iPhone or iPad for full ReplayKit broadcast testing
- An Apple Developer account/team for signing App Groups and the broadcast extension

The project has no third-party package dependencies.

## Project Structure

```text
ReplayConsentRecorder.xcodeproj   Xcode project
ReplayConsentRecorder/            Main SwiftUI app
BroadcastUploadExtension/         ReplayKit broadcast upload extension
```

Important files:

- `ReplayConsentRecorder/ContentView.swift`: main UI, sign-in state, recording controls, screenshots list, and recording list.
- `ReplayConsentRecorder/RecordingManager.swift`: app-only screen recording using `RPScreenRecorder`.
- `ReplayConsentRecorder/RecordingLibrary.swift`: loads and deletes saved broadcast `.mp4` recordings.
- `ReplayConsentRecorder/BroadcastPickerView.swift`: wraps `RPSystemBroadcastPickerView` so the app can open the iOS broadcast picker.
- `BroadcastUploadExtension/SampleHandler.swift`: receives ReplayKit video sample buffers, writes `.mp4` files, and saves broadcast screenshots.

## Setup

1. Open `ReplayConsentRecorder.xcodeproj` in Xcode.

2. Select the `ReplayConsentRecorder` project, then update signing for both targets:

   - `ReplayConsentRecorder`
   - `BroadcastUploadExtension`

3. Replace the placeholder bundle IDs with identifiers owned by your team:

   ```text
   com.example.ReplayConsentRecorder
   com.example.ReplayConsentRecorder.BroadcastUploadExtension
   ```

   For example:

   ```text
   com.yourcompany.ReplayConsentRecorder
   com.yourcompany.ReplayConsentRecorder.BroadcastUploadExtension
   ```

4. Configure the App Group capability for both targets.

   The project currently uses:

   ```text
   group.com.example.ReplayConsentRecorder
   ```

   Replace it with an App Group owned by your Apple Developer team, such as:

   ```text
   group.com.yourcompany.ReplayConsentRecorder
   ```

5. Update the same App Group string in these files:

   - `ReplayConsentRecorder/ReplayConsentRecorder.entitlements`
   - `BroadcastUploadExtension/BroadcastUploadExtension.entitlements`
   - `ReplayConsentRecorder/RecordingLibrary.swift`
   - `BroadcastUploadExtension/SampleHandler.swift`

6. Choose a physical iOS device in Xcode and run the app.

## How to Use

1. Launch the app.
2. Enter any username and password, then sign in by starting a recording.
   The sign-in is local only. It does not call a server.
3. To record only the app screen, tap **Start App Screen Recording**.
4. Tap **Stop and Preview** to stop app recording and show the iOS ReplayKit preview.
5. To record the phone screen, tap **Start Phone Screen Recording**.
6. In the iOS broadcast picker, choose **Phone Screen Recording**.
7. Stop the broadcast from the iOS screen recording indicator or Control Center.
8. Return to the app and refresh **Phone Screen Recordings** to view saved videos.
9. Refresh **Screenshots** to view saved app and phone screenshots.

Saved broadcast recordings are `.mp4` files. Saved screenshots are `.png` files.

## Storage

The main app and extension share files through the configured App Group container.

Inside that shared container:

```text
BroadcastRecordings/   Saved phone screen recordings
AppScreenshots/        Saved app and phone screenshots
```

The app reads files from these folders and lets you preview or delete them from the UI.

## Troubleshooting

- **The app says to enable App Group capability**: make sure both targets use the same App Group identifier and that the identifier is registered in your Apple Developer account.
- **The broadcast extension does not appear in the picker**: confirm the extension target is signed, installed with the app, and has a bundle ID that starts with the main app bundle ID.
- **Phone screen recording does not work in the simulator**: test on a physical iPhone or iPad.
- **Recordings do not show up immediately**: stop the broadcast, reopen the app if needed, then tap the refresh button in the recordings section.
- **Signing fails**: replace the placeholder `com.example` IDs and `group.com.example...` App Group with values owned by your development team.
