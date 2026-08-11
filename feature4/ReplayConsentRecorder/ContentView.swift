import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var recorder: RecordingManager
    @StateObject private var recordingLibrary = RecordingLibrary()
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggedIn = false
    @State private var loginMessage: String?
    @State private var selectedRecording: BroadcastRecording?
    @State private var selectedScreenshot: SavedScreenshot?
    @State private var phoneRecordingRequestID = 0
    @State private var savedScreenshots: [SavedScreenshot] = []
    @State private var screenshotStatusMessage: String?
    @State private var screenshotMessage: String?
    @State private var isScreenshotError = false
    @State private var screenshotTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: recorder.isRecording ? "record.circle.fill" : "record.circle")
                        .font(.system(size: 74, weight: .semibold))
                        .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                        .symbolEffect(.pulse, isActive: recorder.isRecording)

                    VStack(spacing: 10) {
                        Text(recorder.isRecording ? "Recording" : "Ready")
                            .font(.largeTitle.weight(.bold))

                        Text("Use app recording for this screen, or start a phone screen recording to capture the phone screen while this app is in the background.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 330)
                    }

                    loginSection
                    recordingControls
                    recordingsSection
                    screenshotsSection

                    if let message = recorder.statusMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(recorder.statusKind.color)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .navigationTitle("Replay Recorder")
            .onAppear {
                recordingLibrary.refresh()
                refreshScreenshots()
                updateAutomaticScreenshots()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    recordingLibrary.refresh()
                    refreshScreenshots()
                }

                updateAutomaticScreenshots()
            }
            .onChange(of: isLoggedIn) {
                updateAutomaticScreenshots()
            }
            .onDisappear {
                stopAutomaticScreenshots()
            }
            .sheet(item: $recorder.preview) { preview in
                ReplayPreviewSheet(previewController: preview.controller) {
                    recorder.preview = nil
                }
            }
            .sheet(item: $selectedRecording) { recording in
                VideoPlayerSheet(recording: recording)
            }
            .sheet(item: $selectedScreenshot) { screenshot in
                ScreenshotViewerSheet(screenshot: screenshot)
            }
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(isLoggedIn ? "Signed In" : "Sign In", systemImage: isLoggedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                    .font(.headline)

                Spacer()

                if isLoggedIn {
                    Button("Log Out") {
                        isLoggedIn = false
                        password = ""
                        loginMessage = "Signed out."
                        screenshotMessage = nil
                    }
                    .buttonStyle(.borderless)
                }
            }

            if isLoggedIn {
                Text(username)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                Text("The phone screen recording button will sign in first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let loginMessage {
                Text(loginMessage)
                    .font(.footnote)
                    .foregroundStyle(isLoggedIn ? .green : .orange)
            }
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: 360)
    }

    private var screenshotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Screenshots", systemImage: "photo.on.rectangle")
                    .font(.headline)

                Spacer()

                Button {
                    refreshScreenshots()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh Screenshots")
            }

            if savedScreenshots.isEmpty {
                Text(screenshotStatusMessage ?? "Start phone screen recording to save foreground screen screenshots every 5 seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(savedScreenshots) { screenshot in
                    HStack(spacing: 10) {
                        Button {
                            selectedScreenshot = screenshot
                        } label: {
                            Label(screenshot.title, systemImage: "photo")
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            deleteScreenshot(screenshot)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete Screenshot")
                    }
                    .font(.callout)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: 360)
    }

    private var recordingControls: some View {
        VStack(spacing: 12) {
            ZStack {
                BroadcastPickerView(isEnabled: true, activationID: phoneRecordingRequestID)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)

                Button {
                    signInAndStartPhoneRecording()
                } label: {
                    Label(isLoggedIn ? "Start Phone Screen Recording" : "Log In and Start Recording", systemImage: "iphone.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canStartPhoneRecording)
            }

            Button {
                recorder.startRecording()
            } label: {
                Label("Start App Screen Recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(recorder.isRecording || !isLoggedIn)

            Button {
                recorder.stopRecording()
            } label: {
                Label("Stop and Preview", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!recorder.isRecording)

            if let screenshotMessage {
                Text(screenshotMessage)
                    .font(.footnote)
                    .foregroundStyle(isScreenshotError ? .orange : .green)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 360)
    }

    private var canStartPhoneRecording: Bool {
        if isLoggedIn {
            return true
        }

        return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Phone Screen Recordings", systemImage: "film")
                    .font(.headline)

                Spacer()

                Button {
                    recordingLibrary.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh Recordings")
            }

            if recordingLibrary.recordings.isEmpty {
                Text(recordingLibrary.statusMessage ?? "Stop a phone screen recording, then reopen or refresh.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recordingLibrary.recordings) { recording in
                    HStack(spacing: 10) {
                        Button {
                            selectedRecording = recording
                        } label: {
                            Label(recording.title, systemImage: "play.circle")
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            recordingLibrary.delete(recording)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete Recording")
                    }
                    .font(.callout)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: 360)
    }

    private func signIn() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            loginMessage = "Enter a username and password."
            return
        }

        username = trimmedUsername
        password = ""
        isLoggedIn = true
        loginMessage = "Signed in. Start phone screen recording to save foreground screen screenshots every 5 seconds."
    }

    private func signInAndStartPhoneRecording() {
        if !isLoggedIn {
            signIn()
        }

        guard isLoggedIn else {
            return
        }

        phoneRecordingRequestID += 1
    }

    private func updateAutomaticScreenshots() {
        guard isLoggedIn, scenePhase == .active else {
            stopAutomaticScreenshots()
            return
        }

        startAutomaticScreenshots()
    }

    private func startAutomaticScreenshots() {
        guard screenshotTask == nil else {
            return
        }

        setScreenshotMessage("App screenshots save while open. Phone screen screenshots save during phone screen recording.", isError: false)

        screenshotTask = Task { @MainActor in
            while !Task.isCancelled {
                saveAppScreenshot()
                // screenshot interval
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func stopAutomaticScreenshots() {
        screenshotTask?.cancel()
        screenshotTask = nil
    }

    private func makeAppScreenshot() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: \.isKeyWindow) else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale

        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func saveAppScreenshot() {
        guard let image = makeAppScreenshot() else {
            setScreenshotMessage("Could not capture the current app screen.", isError: true)
            return
        }

        guard let data = image.pngData() else {
            setScreenshotMessage("Could not encode screenshot.", isError: true)
            return
        }

        guard let directory = screenshotsDirectory(createIfNeeded: true) else {
            setScreenshotMessage("Enable the App Group capability to save screenshots.", isError: true)
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let url = directory.appendingPathComponent("screenshot-\(timestamp).png")

        do {
            try data.write(to: url, options: [.atomic])
            refreshScreenshots()
            let time = Date().formatted(date: .omitted, time: .standard)
            setScreenshotMessage("Last app screenshot saved at \(time).", isError: false)
        } catch {
            setScreenshotMessage(error.localizedDescription, isError: true)
        }
    }

    private func screenshotsDirectory(createIfNeeded: Bool) -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: RecordingLibrary.appGroupID
        ) else {
            return nil
        }

        let directory = container.appendingPathComponent("AppScreenshots", isDirectory: true)

        if createIfNeeded {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    private func refreshScreenshots() {
        guard let directory = screenshotsDirectory(createIfNeeded: false) else {
            savedScreenshots = []
            screenshotStatusMessage = "Enable the App Group capability to view screenshots."
            return
        }

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            savedScreenshots = urls
                .filter { $0.pathExtension.lowercased() == "png" }
                .compactMap { url in
                    let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                    let createdAt = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                    return SavedScreenshot(id: url, url: url, createdAt: createdAt)
                }
                .sorted { $0.createdAt > $1.createdAt }

            screenshotStatusMessage = savedScreenshots.isEmpty ? "No screenshots saved yet." : nil
        } catch {
            savedScreenshots = []
            screenshotStatusMessage = error.localizedDescription
        }
    }

    private func deleteScreenshot(_ screenshot: SavedScreenshot) {
        do {
            try FileManager.default.removeItem(at: screenshot.url)
            refreshScreenshots()
        } catch {
            screenshotStatusMessage = error.localizedDescription
        }
    }

    private func setScreenshotMessage(_ message: String, isError: Bool) {
        screenshotMessage = message
        isScreenshotError = isError
    }
}

struct SavedScreenshot: Identifiable {
    let id: URL
    let url: URL
    let createdAt: Date

    var title: String {
        "\(sourceLabel) - \(createdAt.formatted(date: .abbreviated, time: .standard))"
    }

    private var sourceLabel: String {
        if url.lastPathComponent.hasPrefix("broadcast-screenshot-") {
            return "Phone"
        }

        return "App"
    }
}

struct ScreenshotViewerSheet: View {
    let screenshot: SavedScreenshot

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(contentsOfFile: screenshot.url.path) {
                    ZoomableImageView(image: image)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("Screenshot Unavailable", systemImage: "photo", description: Text("The screenshot file could not be opened."))
                }
            }
            .navigationTitle(screenshot.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomableImageScrollView {
        ZoomableImageScrollView(image: image)
    }

    func updateUIView(_ scrollView: ZoomableImageScrollView, context: Context) {
        scrollView.setImage(image)
    }
}

final class ZoomableImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var didSetInitialZoom = false

    init(image: UIImage) {
        super.init(frame: .zero)

        delegate = self
        backgroundColor = .systemBackground
        showsVerticalScrollIndicator = true
        showsHorizontalScrollIndicator = true
        bouncesZoom = true
        decelerationRate = .fast

        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        setImage(image)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        guard imageView.image !== image else {
            return
        }

        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        didSetInitialZoom = false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateZoomScales()
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    private func updateZoomScales() {
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else {
            return
        }

        let widthScale = bounds.width / image.size.width
        let heightScale = bounds.height / image.size.height
        let fitScale = min(widthScale, heightScale)

        minimumZoomScale = fitScale
        maximumZoomScale = max(fitScale * 8, 8)

        if !didSetInitialZoom {
            zoomScale = fitScale
            didSetInitialZoom = true
        }
    }

    private func centerImage() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.05 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }

        let point = gesture.location(in: imageView)
        let targetScale = min(maximumZoomScale, minimumZoomScale * 3)
        let width = bounds.width / targetScale
        let height = bounds.height / targetScale
        let rect = CGRect(
            x: point.x - width / 2,
            y: point.y - height / 2,
            width: width,
            height: height
        )
        zoom(to: rect, animated: true)
    }
}
