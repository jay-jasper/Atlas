import CryptoKit
import Foundation
import StoreKit

enum EntitlementProviderFactory {
    static func make() -> any EntitlementProviding {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ATLAS_ALLOW_LOCAL_ENTITLEMENT"] == "1" {
            return LocalEntitlementProvider()
        }
        #endif
        switch DistributionChannel.current {
        case .appStore:
            return StoreKitEntitlementProvider.shared
        case .direct:
            return SignedLicenseEntitlementProvider()
        }
    }
}

final class StoreKitEntitlementProvider: EntitlementProviding {
    static let shared = StoreKitEntitlementProvider()
    static let proProductID = "ai.atlas.pro"

    private let defaults: UserDefaults
    private let cacheKey = "atlas.storeKit.hasVerifiedPro.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func currentEntitlement() -> LocalEntitlementState {
        guard defaults.bool(forKey: cacheKey) else { return .fallback }
        return LocalEntitlementState(
            edition: .pro,
            source: .storeKit,
            note: "Pro purchase verified by the App Store."
        )
    }

    func refreshEntitlement() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.proProductID,
                  transaction.revocationDate == nil else { continue }
            hasPro = true
            break
        }
        defaults.set(hasPro, forKey: cacheKey)
    }

    func purchasePro() async throws {
        let products = try await Product.products(for: [Self.proProductID])
        guard let product = products.first else { throw PurchaseError.productUnavailable }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw PurchaseError.unverifiedTransaction
            }
            await transaction.finish()
            await refreshEntitlement()
        case .pending: throw PurchaseError.pending
        case .userCancelled: throw PurchaseError.cancelled
        @unknown default: throw PurchaseError.unverifiedTransaction
        }
    }
}

enum PurchaseError: LocalizedError {
    case productUnavailable, unverifiedTransaction, pending, cancelled

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "Atlas Pro is not available in this storefront."
        case .unverifiedTransaction: "The App Store transaction could not be verified."
        case .pending: "The purchase is pending approval."
        case .cancelled: "The purchase was cancelled."
        }
    }
}

private struct SignedLicenseDocument: Decodable {
    let edition: AtlasEdition
    let email: String
    let expiresAt: Date?
    let signature: String

    enum CodingKeys: String, CodingKey {
        case edition, email, signature
        case expiresAt = "expires_at"
    }

    var signedMessage: Data {
        let expiry = expiresAt.map { ISO8601DateFormatter().string(from: $0) } ?? "never"
        return Data("\(edition.rawValue)\n\(email)\n\(expiry)".utf8)
    }
}

struct SignedLicenseEntitlementProvider: EntitlementProviding {
    private let licenseURL: URL
    private let publicKey: Data?
    private let now: () -> Date

    init(
        licenseURL: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Atlas/license.json"),
        publicKey: Data? = Bundle.main.object(forInfoDictionaryKey: "AtlasLicensePublicKey")
            .flatMap { $0 as? String }
            .flatMap { Data(base64Encoded: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.licenseURL = licenseURL
        self.publicKey = publicKey
        self.now = now
    }

    func currentEntitlement() -> LocalEntitlementState {
        guard let publicKey,
              let data = try? Data(contentsOf: licenseURL),
              let document = try? JSONDecoder.atlasLicense.decode(SignedLicenseDocument.self, from: data),
              document.expiresAt.map({ $0 > now() }) ?? true,
              let signature = Data(base64Encoded: document.signature),
              let verifier = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              verifier.isValidSignature(signature, for: document.signedMessage) else {
            return .fallback
        }
        return LocalEntitlementState(
            edition: document.edition,
            source: .directLicense,
            note: "Signed license verified for \(document.email)."
        )
    }
}

private extension JSONDecoder {
    static var atlasLicense: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
