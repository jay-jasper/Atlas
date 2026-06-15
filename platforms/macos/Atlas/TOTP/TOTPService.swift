import Foundation

@MainActor
final class TOTPService: ObservableObject {
    @Published private(set) var accounts: [TOTPAccount] = []
    @Published private(set) var statusMessage: String = ""

    private let store: TOTPStoring

    init(store: TOTPStoring = KeychainTOTPStore()) {
        self.store = store
        reload()
    }

    func reload() {
        accounts = store.accounts()
    }

    func add(_ account: TOTPAccount) {
        do {
            try store.add(account)
            statusMessage = ""
            reload()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addFromURI(_ uri: String) {
        guard let account = TOTPAccount.parse(otpauthURI: uri) else {
            statusMessage = "Could not parse otpauth URI."
            return
        }
        add(account)
    }

    func delete(id: UUID) {
        do {
            try store.delete(id: id)
            reload()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func code(for account: TOTPAccount, at date: Date = Date()) -> String {
        TOTPGenerator.code(
            secretBase32: account.secret,
            date: date,
            digits: account.digits,
            period: TimeInterval(account.period)
        ) ?? String(repeating: "•", count: account.digits)
    }

    func secondsRemaining(for account: TOTPAccount, at date: Date = Date()) -> Int {
        TOTPGenerator.secondsRemaining(date: date, period: TimeInterval(account.period))
    }
}
