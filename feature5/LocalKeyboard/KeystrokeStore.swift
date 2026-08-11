import Foundation

struct KeystrokeEvent: Codable, Identifiable, Hashable {
    let id: UUID
    let text: String
    let date: Date

    var displayText: String {
        switch text {
        case " ":
            return "[space]"
        case "\n":
            return "[return]"
        default:
            return text
        }
    }
}

struct KeyboardServerConfig: Codable, Equatable {
    var serverURL: String
    var token: String

    var isReady: Bool {
        KeystrokeStore.serverBaseURL(from: serverURL) != nil &&
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum KeystrokeStore {
    static let appGroupID = "group.com.example.LocalKeyboard"
    static let defaultServerURL = "http://10.132.0.29:8765"
    private static let eventsKey = "keyboardEvents"
    private static let serverConfigKey = "serverConfig"
    private static let maximumEvents = 2_000

    static func load() -> [KeystrokeEvent] {
        guard
            let data = defaults?.data(forKey: eventsKey),
            let events = try? JSONDecoder().decode([KeystrokeEvent].self, from: data)
        else {
            return []
        }

        return events
    }

    static func append(_ text: String) {
        var events = load()
        events.append(KeystrokeEvent(id: UUID(), text: text, date: Date()))

        if events.count > maximumEvents {
            events.removeFirst(events.count - maximumEvents)
        }

        save(events)
    }

    static func clear() {
        defaults?.removeObject(forKey: eventsKey)
    }

    static func loadServerConfig() -> KeyboardServerConfig {
        guard
            let data = defaults?.data(forKey: serverConfigKey),
            let config = try? JSONDecoder().decode(KeyboardServerConfig.self, from: data)
        else {
            let config = KeyboardServerConfig(serverURL: defaultServerURL, token: "")
            saveServerConfig(config)
            return config
        }

        return config
    }

    static func saveServerConfig(_ config: KeyboardServerConfig) {
        let config = KeyboardServerConfig(
            serverURL: normalizedServerURL(from: config.serverURL),
            token: config.token
        )

        guard let data = try? JSONEncoder().encode(config) else {
            return
        }

        defaults?.set(data, forKey: serverConfigKey)
    }

    static func serverBaseURL(from rawValue: String) -> URL? {
        URL(string: normalizedServerURL(from: rawValue))
    }

    static func normalizedServerURL(from rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return value
        }

        if value.contains("://") {
            return value
        }

        return "http://\(value)"
    }

    private static func save(_ events: [KeystrokeEvent]) {
        guard let data = try? JSONEncoder().encode(events) else {
            return
        }

        defaults?.set(data, forKey: eventsKey)
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

}
