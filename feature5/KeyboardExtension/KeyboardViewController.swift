import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController {
    private let rows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
        ["space", "delete", "return"]
    ]
    private var statusLabel: UILabel?
    private var pollTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildKeyboard()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startRemotePolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopRemotePolling()
    }

    private func buildKeyboard() {
        view.backgroundColor = UIColor.systemGray6

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let status = UILabel()
        status.text = "Local Keyboard"
        status.font = .preferredFont(forTextStyle: .caption1)
        status.textColor = .secondaryLabel
        status.textAlignment = .center
        statusLabel = status
        stack.addArrangedSubview(status)

        for row in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 6

            for key in row {
                rowStack.addArrangedSubview(makeButton(for: key))
            }

            stack.addArrangedSubview(rowStack)
        }

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    private func makeButton(for key: String) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title(for: key)
        configuration.baseBackgroundColor = UIColor.systemBackground
        configuration.baseForegroundColor = UIColor.label
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 4)

        let button = UIButton(configuration: configuration)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.accessibilityLabel = accessibilityLabel(for: key)
        button.addAction(UIAction { [weak self] _ in
            self?.handleKey(key)
        }, for: .touchUpInside)
        return button
    }

    private func handleKey(_ key: String) {
        switch key {
        case "space":
            textDocumentProxy.insertText(" ")
            KeystrokeStore.append(" ")
        case "delete":
            textDocumentProxy.deleteBackward()
            KeystrokeStore.append("[delete]")
        case "return":
            textDocumentProxy.insertText("\n")
            KeystrokeStore.append("\n")
        default:
            let text = key.lowercased()
            textDocumentProxy.insertText(text)
            KeystrokeStore.append(text)
        }
    }

    private func startRemotePolling() {
        pollTask?.cancel()
        updateStatus("Remote input ready")
        pollTask = Task { [weak self] in
            await self?.pollRemoteInput()
        }
    }

    private func stopRemotePolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollRemoteInput() async {
        while !Task.isCancelled {
            await fetchNextRemoteInput()
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
    }

    private func fetchNextRemoteInput() async {
        let config = KeystrokeStore.loadServerConfig()
        guard config.isReady, let requestURL = nextInputURL(config: config) else {
            updateStatus("Set server in app")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: requestURL)
            guard
                let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200,
                let payload = try? JSONDecoder().decode(RemoteInputResponse.self, from: data)
            else {
                updateStatus("Remote input rejected")
                return
            }

            guard let text = payload.text, !text.isEmpty else {
                updateStatus("Remote input ready")
                return
            }

            textDocumentProxy.insertText(text)
            KeystrokeStore.append("[remote] \(text)")
            updateStatus("Inserted remote input")
        } catch {
            updateStatus("Remote input offline")
        }
    }

    private func nextInputURL(config: KeyboardServerConfig) -> URL? {
        guard let baseURL = KeystrokeStore.serverBaseURL(from: config.serverURL) else {
            return nil
        }

        let endpoint = baseURL.appendingPathComponent("next")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "token", value: config.token)
        ]
        return components.url
    }

    private func updateStatus(_ text: String) {
        statusLabel?.text = text
    }

    private func title(for key: String) -> String {
        switch key {
        case "space":
            return "space"
        case "delete":
            return "⌫"
        case "return":
            return "return"
        default:
            return key
        }
    }

    private func accessibilityLabel(for key: String) -> String {
        switch key {
        case "space":
            return "Space"
        case "delete":
            return "Delete"
        case "return":
            return "Return"
        default:
            return key
        }
    }
}

private struct RemoteInputResponse: Decodable {
    let text: String?
}
