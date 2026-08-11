import SwiftUI

@main
struct ReplayConsentRecorderApp: App {
    @StateObject private var recorder = RecordingManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recorder)
        }
    }
}
