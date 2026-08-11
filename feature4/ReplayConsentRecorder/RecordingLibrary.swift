import Foundation

struct BroadcastRecording: Identifiable {
    let id: URL
    let url: URL
    let createdAt: Date

    var title: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

@MainActor
final class RecordingLibrary: ObservableObject {
    static let appGroupID = "group.com.example.ReplayConsentRecorder"
    static let folderName = "BroadcastRecordings"

    @Published private(set) var recordings: [BroadcastRecording] = []
    @Published private(set) var statusMessage: String?

    func refresh() {
        guard let directory = Self.recordingsDirectory(createIfNeeded: false) else {
            recordings = []
            statusMessage = "Enable the App Group capability to view broadcast recordings."
            return
        }

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            recordings = urls
                .filter { $0.pathExtension.lowercased() == "mp4" }
                .compactMap { url in
                    let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                    let createdAt = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                    return BroadcastRecording(id: url, url: url, createdAt: createdAt)
                }
                .sorted { $0.createdAt > $1.createdAt }

            statusMessage = recordings.isEmpty ? "No broadcast recordings yet." : nil
        } catch {
            recordings = []
            statusMessage = error.localizedDescription
        }
    }

    func delete(_ recording: BroadcastRecording) {
        do {
            try FileManager.default.removeItem(at: recording.url)
            refresh()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    static func recordingsDirectory(createIfNeeded: Bool) -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }

        let directory = container.appendingPathComponent(folderName, isDirectory: true)

        if createIfNeeded {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }
}
