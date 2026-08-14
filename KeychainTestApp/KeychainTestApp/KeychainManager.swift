import Foundation
import Security

enum KeychainManager {
    static let service = "com.example.KeychainTestApp"
    static let account = "test-user"
    static let testSecret = "TEST_KEYCHAIN_SECRET_12345"

    struct ReadResult {
        let status: OSStatus
        let value: String?
    }

    struct AutomatedTestResult {
        let deleteStatus: OSStatus
        let addStatus: OSStatus
        let readStatus: OSStatus
        let matchedExpectedValue: Bool

        var passed: Bool {
            addStatus == errSecSuccess && readStatus == errSecSuccess && matchedExpectedValue
        }
    }

    static func saveSecret(_ secret: String) -> OSStatus {
        let secretData = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: secretData
        ]

        print("[KeychainTest] Calling SecItemAdd")
        let status = SecItemAdd(query as CFDictionary, nil)
        print("[KeychainTest] SecItemAdd returned: \(status)")

        return status
    }

    static func readSecret() -> ReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?

        print("[KeychainTest] Calling SecItemCopyMatching")
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        print("[KeychainTest] SecItemCopyMatching returned: \(status)")

        guard status == errSecSuccess else {
            return ReadResult(status: status, value: nil)
        }

        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            print("[KeychainTest] Retrieved Keychain data could not be decoded as UTF-8")
            return ReadResult(status: status, value: nil)
        }

        print("[KeychainTest] Retrieved Keychain value")
        return ReadResult(status: status, value: value)
    }

    static func deleteSecret() -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        print("[KeychainTest] Calling SecItemDelete")
        let status = SecItemDelete(query as CFDictionary)
        print("[KeychainTest] SecItemDelete returned: \(status)")

        return status
    }

    static func runAutomatedTest() -> AutomatedTestResult {
        let deleteStatus = deleteSecret()
        let addStatus = saveSecret(testSecret)
        let readResult = readSecret()
        let matched = readResult.value == testSecret

        return AutomatedTestResult(
            deleteStatus: deleteStatus,
            addStatus: addStatus,
            readStatus: readResult.status,
            matchedExpectedValue: matched
        )
    }
}
