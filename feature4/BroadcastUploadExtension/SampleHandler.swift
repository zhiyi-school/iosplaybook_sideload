import AVFoundation
import CoreImage
import ImageIO
import ReplayKit
import UniformTypeIdentifiers

final class SampleHandler: RPBroadcastSampleHandler {
    private static let appGroupID = "group.com.example.ReplayConsentRecorder"
    private static let recordingFolderName = "BroadcastRecordings"
    private static let screenshotFolderName = "AppScreenshots"
    private static let screenshotInterval: TimeInterval = 5

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var recordingURL: URL?
    private let imageContext = CIContext()
    private var lastScreenshotDate: Date?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let directory = recordingsDirectory() else {
            finishBroadcastWithError(BroadcastRecordingError.sharedContainerUnavailable)
            return
        }

        lastScreenshotDate = nil
        recordingURL = directory
            .appendingPathComponent("broadcast-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("mp4")
    }

    override func broadcastPaused() {
    }

    override func broadcastResumed() {
    }

    override func broadcastFinished() {
        lastScreenshotDate = nil
        finishRecording()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            appendVideoSampleBuffer(sampleBuffer)
        case .audioApp:
            break
        case .audioMic:
            break
        @unknown default:
            break
        }
    }

    private func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        saveBroadcastScreenshotIfNeeded(from: sampleBuffer)

        if assetWriter == nil {
            prepareWriter(using: sampleBuffer)
        }

        guard
            let assetWriter,
            let videoInput,
            assetWriter.status == .writing,
            videoInput.isReadyForMoreMediaData
        else {
            return
        }

        videoInput.append(sampleBuffer)
    }

    private func prepareWriter(using sampleBuffer: CMSampleBuffer) {
        guard
            let recordingURL,
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        else {
            return
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dimensions.width),
            AVVideoHeightKey: Int(dimensions.height)
        ]

        do {
            let writer = try AVAssetWriter(outputURL: recordingURL, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true

            if writer.canAdd(input) {
                writer.add(input)
            }

            let firstPresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: firstPresentationTime)

            assetWriter = writer
            videoInput = input
        } catch {
            finishBroadcastWithError(error)
        }
    }

    private func finishRecording() {
        guard let assetWriter else {
            return
        }

        videoInput?.markAsFinished()
        assetWriter.finishWriting { }

        self.assetWriter = nil
        videoInput = nil
    }

    private func recordingsDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            return nil
        }

        let directory = container.appendingPathComponent(Self.recordingFolderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            finishBroadcastWithError(error)
            return nil
        }
    }

    private func saveBroadcastScreenshotIfNeeded(from sampleBuffer: CMSampleBuffer) {
        let now = Date()

        if let lastScreenshotDate,
           now.timeIntervalSince(lastScreenshotDate) < Self.screenshotInterval {
            return
        }

        guard
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let directory = screenshotsDirectory()
        else {
            return
        }

        let timestamp = Int(now.timeIntervalSince1970 * 1000)
        let url = directory.appendingPathComponent("broadcast-screenshot-\(timestamp).png")
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)

        guard
            let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            return
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        if CGImageDestinationFinalize(destination) {
            lastScreenshotDate = now
        }
    }

    private func screenshotsDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            return nil
        }

        let directory = container.appendingPathComponent(Self.screenshotFolderName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }
}

enum BroadcastRecordingError: LocalizedError {
    case sharedContainerUnavailable

    var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable:
            return "The shared App Group container is not available."
        }
    }
}
