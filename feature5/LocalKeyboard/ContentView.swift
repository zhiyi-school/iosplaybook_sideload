import SwiftUI

struct ContentView: View {
    @State private var events: [KeystrokeEvent] = KeystrokeStore.load()
    @State private var serverConfig: KeyboardServerConfig = KeystrokeStore.loadServerConfig()
    @State private var pairingStatus: String = "Waiting for server"
    @State private var isPairing = false
    @State private var autoPairTask: Task<Void, Never>?

    private var groupedEvents: [KeystrokeEvent] {
        events.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(events.count)")
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                            Text("stored keyboard events")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            events = KeystrokeStore.load()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Refresh")
                    }
                    .padding(.vertical, 8)
                }

                Section("Remote Input") {
                    TextField("Server IP:Port", text: $serverConfig.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("server-url-input")

                    Text(serverConfig.token.isEmpty ? "No token yet" : serverConfig.token)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("pairing-token-text")

                    Label(pairingStatus, systemImage: isPairing ? "arrow.triangle.2.circlepath" : "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("pairing-status-label")
                }

                Section("Events") {
                    if groupedEvents.isEmpty {
                        ContentUnavailableView(
                            "No Events",
                            systemImage: "keyboard",
                            description: Text("Typed keys from the enabled custom keyboard appear here.")
                        )
                    } else {
                        ForEach(groupedEvents) { event in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(event.displayText)
                                    .font(.body.monospaced())
                                Text(event.date.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Local Keyboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        KeystrokeStore.clear()
                        events = []
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear Events")
                    .disabled(events.isEmpty)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                events = KeystrokeStore.load()
                serverConfig = KeystrokeStore.loadServerConfig()
                scheduleAutomaticPairing(delay: 0)
            }
            .onChange(of: serverConfig.serverURL) { _, _ in
                serverConfig.token = ""
                KeystrokeStore.saveServerConfig(serverConfig)
                scheduleAutomaticPairing(delay: 0.6)
            }
            .task {
                await pairWithServer()
            }
        }
    }

    @MainActor
    private func pairWithServer() async {
        guard let pairURL = pairURL else {
            pairingStatus = "Enter a valid server URL"
            return
        }

        isPairing = true
        pairingStatus = "Pairing..."
        defer {
            isPairing = false
        }

        do {
            let pairing = try await requestPairingToken(from: pairURL)
            serverConfig.token = pairing.token
            KeystrokeStore.saveServerConfig(serverConfig)
            pairingStatus = "Paired"
        } catch PairingError.alreadyPaired {
            pairingStatus = "Already paired"
        } catch PairingError.rejected(let reason) {
            pairingStatus = "Pairing rejected: \(reason)"
        } catch {
            pairingStatus = "Pairing failed: \(error.localizedDescription)"
        }
    }

    private func requestPairingToken(from pairURL: URL) async throws -> ServerPairingResponse {
        do {
            return try await requestPairingToken(from: postPairRequest(url: pairURL))
        } catch PairingError.rejected(let reason)
            where reason == "not_found" || reason == "HTTP 405" {
            return try await requestPairingToken(from: URLRequest(url: pairURL))
        }
    }

    private func requestPairingToken(from request: URLRequest) async throws -> ServerPairingResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PairingError.rejected(reason: "invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let reason = pairingErrorReason(from: data) ?? "HTTP \(httpResponse.statusCode)"
            if httpResponse.statusCode == 409,
               reason == "pairing_closed",
               !serverConfig.token.isEmpty {
                throw PairingError.alreadyPaired
            }

            throw PairingError.rejected(reason: reason)
        }

        guard let pairing = try? JSONDecoder().decode(ServerPairingResponse.self, from: data) else {
            throw PairingError.rejected(reason: "invalid JSON")
        }

        guard !pairing.token.isEmpty else {
            throw PairingError.rejected(reason: "empty token")
        }

        return pairing
    }

    private func postPairRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"client":"LocalKeyboard"}"#.utf8)
        return request
    }

    @MainActor
    private func scheduleAutomaticPairing(delay: TimeInterval) {
        autoPairTask?.cancel()
        autoPairTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard !Task.isCancelled else {
                return
            }

            await pairWithServer()
        }
    }

    private var pairURL: URL? {
        guard let baseURL = KeystrokeStore.serverBaseURL(from: serverConfig.serverURL) else {
            return nil
        }

        return baseURL.appendingPathComponent("pair")
    }

    private func pairingErrorReason(from data: Data) -> String? {
        if let serverError = try? JSONDecoder().decode(ServerErrorResponse.self, from: data),
           !serverError.error.isEmpty {
            return serverError.error
        }

        let body = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }
}

private struct ServerPairingResponse: Decodable {
    let token: String
}

private struct ServerErrorResponse: Decodable {
    let error: String
}

private enum PairingError: LocalizedError {
    case alreadyPaired
    case rejected(reason: String)

    var errorDescription: String? {
        switch self {
        case .alreadyPaired:
            return "Already paired"
        case .rejected(let reason):
            return reason
        }
    }
}
