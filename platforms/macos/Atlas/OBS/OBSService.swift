import Foundation

@MainActor
final class OBSService: ObservableObject {
    @Published var host = "localhost"
    @Published var port = "4455"
    @Published var password = ""
    @Published private(set) var isConnected = false
    @Published private(set) var statusMessage = ""

    private var task: URLSessionWebSocketTask?
    private var requestCounter = 0

    func connect() {
        guard let url = URL(string: "ws://\(host):\(port)") else {
            statusMessage = "Invalid host/port."
            return
        }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        statusMessage = "Connecting…"
        receive()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
        statusMessage = "Disconnected."
    }

    func setScene(_ name: String) {
        send(OBSMessage.setSceneRequest(name, requestId: nextRequestId()))
    }

    func toggleRecord() {
        send(OBSMessage.toggleRecordRequest(requestId: nextRequestId()))
    }

    func toggleStream() {
        send(OBSMessage.toggleStreamRequest(requestId: nextRequestId()))
    }

    // MARK: - Plumbing

    private func nextRequestId() -> String {
        requestCounter += 1
        return "atlas-\(requestCounter)"
    }

    private func send(_ message: [String: Any]) {
        guard let data = OBSMessage.encode(message), let task else { return }
        task.send(.data(data)) { [weak self] error in
            if error != nil {
                Task { @MainActor in self?.statusMessage = "Send failed." }
            }
        }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let data: Data?
                switch message {
                case .data(let d): data = d
                case .string(let s): data = s.data(using: .utf8)
                @unknown default: data = nil
                }
                if let data { Task { @MainActor in self.handle(data) } }
                Task { @MainActor in self.receive() }
            case .failure:
                Task { @MainActor in
                    self.isConnected = false
                    self.statusMessage = "Connection closed."
                }
            }
        }
    }

    private func handle(_ data: Data) {
        guard let parsed = OBSMessage.parse(data) else { return }
        switch parsed.op {
        case .hello:
            let auth = parsed.data["authentication"] as? [String: Any]
            send(OBSMessage.identify(
                password: password,
                challenge: auth?["challenge"] as? String,
                salt: auth?["salt"] as? String
            ))
        case .identified:
            isConnected = true
            statusMessage = "Connected to OBS."
        default:
            break
        }
    }
}
