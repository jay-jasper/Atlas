import Foundation
import Network

/// A discovered peer on the local network.
struct TransferPeer: Equatable, Identifiable {
    var id: String { name }
    let name: String
}

@MainActor
final class LANTransferService: ObservableObject {
    @Published private(set) var isAdvertising = false
    @Published private(set) var peers: [TransferPeer] = []
    @Published private(set) var statusMessage = ""
    @Published private(set) var incomingBuffer = Data()

    private static let serviceType = "_atlasdrop._tcp"
    private var listener: NWListener?
    private var browser: NWBrowser?

    /// Starts advertising this Mac for incoming transfers via Bonjour.
    func startReceiving() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                Task { @MainActor in self?.receive(on: connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
            isAdvertising = true
            statusMessage = "Ready to receive."
            PrivacyPulseReporter.shared.network("LAN Transfer", detail: "Advertising a Bonjour receiver on the local network")
        } catch {
            statusMessage = "Could not start receiver."
        }
    }

    func stopReceiving() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
    }

    /// Browses for nearby Atlas peers.
    func browse() {
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.peers = results.compactMap { result in
                    if case let .service(name, _, _, _) = result.endpoint {
                        return TransferPeer(name: name)
                    }
                    return nil
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// Feeds received bytes through the framing decoder (also used by tests).
    func handleIncoming(_ data: Data) -> [TransferMessage] {
        incomingBuffer.append(data)
        let (messages, remainder) = TransferFraming.drain(incomingBuffer)
        incomingBuffer = remainder
        return messages
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let data, !data.isEmpty {
                Task { @MainActor in _ = self?.handleIncoming(data) }
            }
            if error == nil { self?.receive(on: connection) }
        }
    }
}
