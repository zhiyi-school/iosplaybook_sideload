import LocalAuthentication
import SwiftUI

struct ContentView: View {
    @State private var balance = 18420.75
    @State private var recipient = "Apex Payroll Services"
    @State private var amount = "1250.00"
    @State private var status: TransferStatus = .idle
    @State private var lastConfirmation: String?

    private let session = UserSession(userID: "user_1832", accessToken: "demo-session-token")

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Account", value: "Operating 8421")
                    LabeledContent("Available", value: balance.formatted(.currency(code: "USD")))
                }

                Section("Transfer") {
                    TextField("Recipient", text: $recipient)
                        .textContentType(.organizationName)
                        .textInputAutocapitalization(.words)

                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                }

                Section("Approval") {
                    HStack {
                        Image(systemName: status.icon)
                            .foregroundStyle(status.color)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.title)
                                .font(.headline)
                            Text(status.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let lastConfirmation {
                        LabeledContent("Confirmation", value: lastConfirmation)
                    }

                    Button(action: approveAndSubmitTransfer) {
                        Label("Send Transfer", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSubmit || status == .submitting)

                    Button("Reset Demo", action: resetDemo)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Atlas Bank")
        }
    }

    private var transferAmount: Double? {
        Double(amount.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSubmit: Bool {
        guard let value = transferAmount else { return false }
        return !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value > 0 && value <= balance
    }

    private func approveAndSubmitTransfer() {
        guard let value = transferAmount, canSubmit else {
            status = .failed("Check the recipient and amount.")
            return
        }

        status = .waitingForBiometrics
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            status = .failed(error?.localizedDescription ?? "Biometric approval is unavailable.")
            return
        }

        let reason = "Approve \(value.formatted(.currency(code: "USD"))) transfer to \(recipient)"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            Task { @MainActor in
                guard success else {
                    status = .failed(error?.localizedDescription ?? "Biometric approval was not completed.")
                    return
                }

                await submitTransfer(value)
            }
        }
    }

    @MainActor
    private func submitTransfer(_ value: Double) async {
        status = .submitting

        let transfer = TransferRequest(
            recipient: recipient,
            amount: value,
            localBiometricApproved: true
        )

        do {
            let response = try await MockBankAPI.submitTransfer(transfer, session: session)
            balance -= value
            lastConfirmation = response.confirmationID
            status = .submitted(response.confirmationID)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func resetDemo() {
        balance = 18420.75
        recipient = "Apex Payroll Services"
        amount = "1250.00"
        status = .idle
        lastConfirmation = nil
    }
}

private struct UserSession {
    let userID: String
    let accessToken: String
}

private struct TransferRequest {
    let recipient: String
    let amount: Double
    let localBiometricApproved: Bool
}

private struct TransferResponse {
    let confirmationID: String
}

private enum MockBankAPI {
    static func submitTransfer(_ transfer: TransferRequest, session: UserSession) async throws -> TransferResponse {
        try await Task.sleep(nanoseconds: 450_000_000)

        guard !session.accessToken.isEmpty else {
            throw TransferError.invalidSession
        }

        guard transfer.localBiometricApproved else {
            throw TransferError.stepUpRequired
        }

        return TransferResponse(confirmationID: "AT-\(Int.random(in: 100000...999999))")
    }
}

private enum TransferError: LocalizedError {
    case invalidSession
    case stepUpRequired

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            return "Session is no longer valid."
        case .stepUpRequired:
            return "Biometric step-up is required."
        }
    }
}

private enum TransferStatus: Equatable {
    case idle
    case waitingForBiometrics
    case submitting
    case submitted(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .waitingForBiometrics:
            return "Biometric Approval"
        case .submitting:
            return "Submitting"
        case .submitted:
            return "Transfer Sent"
        case .failed:
            return "Transfer Blocked"
        }
    }

    var message: String {
        switch self {
        case .idle:
            return "High-value transfers require Face ID or Touch ID."
        case .waitingForBiometrics:
            return "Confirm the payment on this device."
        case .submitting:
            return "Sending the approved transfer to the bank API."
        case .submitted(let confirmationID):
            return "The bank API accepted confirmation \(confirmationID)."
        case .failed(let reason):
            return reason
        }
    }

    var icon: String {
        switch self {
        case .idle:
            return "lock.shield"
        case .waitingForBiometrics:
            return "faceid"
        case .submitting:
            return "arrow.triangle.2.circlepath"
        case .submitted:
            return "checkmark.seal.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle, .waitingForBiometrics, .submitting:
            return .indigo
        case .submitted:
            return .green
        case .failed:
            return .red
        }
    }
}
