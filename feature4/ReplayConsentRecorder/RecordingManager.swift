import Foundation
import ReplayKit
import SwiftUI

@MainActor
final class RecordingManager: ObservableObject {
    struct Preview: Identifiable {
        let id = UUID()
        let controller: RPPreviewViewController
    }

    enum StatusKind {
        case neutral
        case success
        case warning

        var color: Color {
            switch self {
            case .neutral:
                return .secondary
            case .success:
                return .green
            case .warning:
                return .orange
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published var preview: Preview?
    @Published var statusMessage: String?
    @Published var statusKind: StatusKind = .neutral

    private let screenRecorder = RPScreenRecorder.shared()

    init() {
        isRecording = screenRecorder.isRecording
    }

    func startRecording() {
        guard screenRecorder.isAvailable else {
            setStatus("Screen recording is not available on this device right now.", kind: .warning)
            return
        }

        guard !screenRecorder.isRecording else {
            isRecording = true
            setStatus("Recording is already running.", kind: .neutral)
            return
        }

        screenRecorder.isMicrophoneEnabled = false
        setStatus("Requesting iOS recording permission...", kind: .neutral)

        screenRecorder.startRecording { [weak self] error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.isRecording = false
                    self.setStatus(error.localizedDescription, kind: .warning)
                    return
                }

                self.isRecording = true
                self.setStatus("Recording started.", kind: .success)
            }
        }
    }

    func stopRecording() {
        guard screenRecorder.isRecording else {
            isRecording = false
            setStatus("No recording is currently running.", kind: .neutral)
            return
        }

        screenRecorder.stopRecording { [weak self] previewController, error in
            Task { @MainActor in
                guard let self else { return }

                self.isRecording = false

                if let error {
                    self.setStatus(error.localizedDescription, kind: .warning)
                    return
                }

                if let previewController {
                    self.preview = Preview(controller: previewController)
                    self.setStatus("Recording stopped. Preview is ready.", kind: .success)
                } else {
                    self.setStatus("Recording stopped.", kind: .success)
                }
            }
        }
    }

    private func setStatus(_ message: String, kind: StatusKind) {
        statusMessage = message
        statusKind = kind
    }
}
