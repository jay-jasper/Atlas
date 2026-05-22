import Foundation

protocol TokenBarUsageImporting {
    func importUsage() throws -> TokenBarSummary
}

struct TokenBarProviderUsageImporter: TokenBarUsageImporting {
    let configStore: TokenBarConfigurationStore
    let ledger: TokenBarLedger
    let client: TokenBarProviderClient
    let now: () -> Date

    init(
        configStore: TokenBarConfigurationStore = TokenBarConfigurationStore(),
        ledger: TokenBarLedger = TokenBarLedger(),
        client: TokenBarProviderClient = TokenBarProviderClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.configStore = configStore
        self.ledger = ledger
        self.client = client
        self.now = now
    }

    func importUsage() throws -> TokenBarSummary {
        guard let config = configStore.load() else {
            throw CocoaError(.userCancelled)
        }

        let entry = try client.fetchCurrentUsage(config: config, now: now())
        try ledger.append(entry)
        return try ledger.summary()
    }
}
