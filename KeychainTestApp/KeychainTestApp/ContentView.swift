import SwiftUI

struct ContentView: View {
    @State private var secretValue = ""
    @State private var logText = "Keychain Test App ready."

    var body: some View {
        NavigationStack {
            Form {
                Section("Secret Value") {
                    TextField("Secret Value", text: $secretValue)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Keychain Operations") {
                    Button(action: saveToKeychain) {
                        Label("Save to Keychain", systemImage: "tray.and.arrow.down")
                    }

                    Button(action: readFromKeychain) {
                        Label("Read from Keychain", systemImage: "key")
                    }

                    Button(role: .destructive, action: deleteFromKeychain) {
                        Label("Delete from Keychain", systemImage: "trash")
                    }

                    Button(action: runKeychainTest) {
                        Label("Run Keychain Test", systemImage: "checkmark.seal")
                    }
                    .font(.headline)
                }

                Section("Results") {
                    ScrollView {
                        Text(logText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 220, alignment: .topLeading)
                }
            }
            .navigationTitle("Keychain Test")
        }
    }

    private func saveToKeychain() {
        let status = KeychainManager.saveSecret(secretValue)
        logText = """
        Save to Keychain

        SecItemAdd: \(status)
        Success: \(status == errSecSuccess ? "YES" : "NO")
        """
    }

    private func readFromKeychain() {
        let result = KeychainManager.readSecret()

        logText = """
        Read from Keychain

        SecItemCopyMatching: \(result.status)
        Retrieved value: \(result.value ?? "<none>")
        Success: \(result.status == errSecSuccess ? "YES" : "NO")
        """
    }

    private func deleteFromKeychain() {
        let status = KeychainManager.deleteSecret()
        let success = status == errSecSuccess || status == errSecItemNotFound

        logText = """
        Delete from Keychain

        SecItemDelete: \(status)
        Success: \(success ? "YES" : "NO")
        """
    }

    private func runKeychainTest() {
        let result = KeychainManager.runAutomatedTest()

        logText = """
        Keychain Test

        SecItemDelete: \(result.deleteStatus)
        SecItemAdd: \(result.addStatus)
        SecItemCopyMatching: \(result.readStatus)
        Retrieved value matched expected value: \(result.matchedExpectedValue ? "YES" : "NO")

        RESULT: \(result.passed ? "PASS" : "FAIL")
        """
    }
}
