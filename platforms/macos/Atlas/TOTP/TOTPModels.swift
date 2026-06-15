import Foundation

struct TOTPAccount: Codable, Equatable, Identifiable {
    var id: UUID
    var issuer: String
    var label: String
    var secret: String
    var digits: Int
    var period: Int

    init(id: UUID = UUID(), issuer: String, label: String, secret: String, digits: Int = 6, period: Int = 30) {
        self.id = id
        self.issuer = issuer
        self.label = label
        self.secret = secret
        self.digits = digits
        self.period = period
    }

    var isValid: Bool {
        !issuer.trimmingCharacters(in: .whitespaces).isEmpty &&
        TOTPGenerator.base32Decode(secret) != nil
    }

    /// Parses an `otpauth://totp/...` URI (e.g. from a QR code) into an account.
    static func parse(otpauthURI: String) -> TOTPAccount? {
        guard let components = URLComponents(string: otpauthURI),
              components.scheme == "otpauth",
              components.host == "totp" else { return nil }
        let queryItems = components.queryItems ?? []
        guard let secret = queryItems.first(where: { $0.name == "secret" })?.value,
              TOTPGenerator.base32Decode(secret) != nil else { return nil }

        let path = components.path.hasPrefix("/") ? String(components.path.dropFirst()) : components.path
        let labelParts = path.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        let queryIssuer = queryItems.first(where: { $0.name == "issuer" })?.value
        let issuer = queryIssuer ?? (labelParts.count > 1 ? labelParts[0] : path)
        let label = labelParts.count > 1 ? labelParts[1] : path
        let digits = queryItems.first(where: { $0.name == "digits" })?.value.flatMap(Int.init) ?? 6
        let period = queryItems.first(where: { $0.name == "period" })?.value.flatMap(Int.init) ?? 30

        return TOTPAccount(issuer: issuer, label: label, secret: secret, digits: digits, period: period)
    }
}
