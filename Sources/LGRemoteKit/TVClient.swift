import Foundation

public enum TVError: LocalizedError {
    case notConnected
    case invalidAddress(String)
    case pairingRejected(String)
    case timeout(String)
    case tv(String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to the TV."
        case .invalidAddress(let host): return "\"\(host)\" is not a valid TV address."
        case .pairingRejected(let reason): return "The TV refused pairing: \(reason)"
        case .timeout(let what): return "The TV did not answer: \(what)"
        case .tv(let message): return "The TV answered with an error: \(message)"
        case .badResponse(let what): return "Unexpected answer from the TV: \(what)"
        }
    }
}

/// Talks to an LG webOS TV over its local SSAP WebSocket API (wss, port 3001).
///
/// Pairing uses an unsigned manifest: recent firmware rejects the signed manifest that
/// third-party clients share ("403 Pairing rejected: blacklisted certificate detected"),
/// but still accepts an unsigned one after the user confirms the prompt on the TV.
public actor TVClient {
    public typealias JSON = [String: Any]
    static let port = 3001
    private static let requestTimeout: Duration = .seconds(10)
    private static let pairingTimeout: Duration = .seconds(60)

    private let host: String
    private let keyStore: KeyStore
    nonisolated private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var pointerSocket: Task<URLSessionWebSocketTask, Error>?
    private var pending: [String: (reply: CheckedContinuation<JSON, Error>, timeout: Task<Void, Never>)] = [:]
    private var nextId = 0
    private var onDisconnect: (@Sendable () -> Void)?

    public init(host: String, keyStore: KeyStore) {
        self.host = host
        self.keyStore = keyStore
        self.session = URLSession(
            configuration: .ephemeral,
            delegate: TVTrustDelegate(host: host, port: Self.port),
            delegateQueue: nil
        )
    }

    public var isConnected: Bool { socket != nil }

    /// Called when the TV drops an open connection (turned off, Wi-Fi lost).
    public func setDisconnectHandler(_ handler: @escaping @Sendable () -> Void) {
        onDisconnect = handler
    }

    /// Opens the socket and registers. Without a stored key the TV shows a prompt,
    /// so this waits up to a minute for the user to accept it.
    public func connect() async throws {
        disconnect()
        guard let url = onTVHost("wss://localhost") else { throw TVError.invalidAddress(host) }
        let task = session.webSocketTask(with: url)
        task.resume()
        socket = task
        listen(task)

        let storedKey = keyStore.key(for: host)
        var payload: JSON = ["forcePairing": false, "pairingType": "PROMPT", "manifest": Manifest.unsigned]
        if let storedKey { payload["client-key"] = storedKey }
        do {
            let response = try await send(
                type: "register", uri: nil, payload: payload,
                timeout: storedKey == nil ? Self.pairingTimeout : Self.requestTimeout
            )
            guard let key = response["client-key"] as? String else {
                throw TVError.badResponse("registration without a client key")
            }
            if key != storedKey { keyStore.setKey(key, for: host) }
        } catch {
            disconnect()
            throw error
        }
    }

    public func disconnect() {
        close(failing: TVError.notConnected)
    }

    /// Disconnects and releases the URL session. The client cannot be used afterwards.
    public func shutdown() {
        disconnect()
        session.invalidateAndCancel()
    }

    /// Sends an SSAP request such as `ssap://audio/getVolume` and returns its payload.
    @discardableResult
    public func request(_ uri: String, _ payload: JSON = [:]) async throws -> JSON {
        try await send(type: "request", uri: uri, payload: payload, timeout: Self.requestTimeout)
    }

    /// Presses a remote button (UP, DOWN, LEFT, RIGHT, ENTER, BACK, HOME, MENU, ...).
    /// Long presses are not supported by the TV's pointer socket.
    public func press(_ button: String) async throws {
        try await pointer().send(.string("type:button\nname:\(button)\n\n"))
    }

    /// Captures the screen. Protected content (Netflix, HDMI, Live TV) comes back black.
    public func screenshot() async throws -> Data {
        let response = try await request("ssap://tv/executeOneShot")
        guard let uri = response["imageUri"] as? String, let url = onTVHost(uri) else {
            throw TVError.badResponse("screenshot without an image address")
        }
        let (data, _) = try await session.data(from: url)
        return data
    }

    // MARK: - Socket plumbing

    private func pointer() async throws -> URLSessionWebSocketTask {
        if let pointerSocket { return try await pointerSocket.value }
        // Store the task before awaiting so concurrent presses share one socket.
        let task = Task { () throws -> URLSessionWebSocketTask in
            let response = try await self.request("ssap://com.webos.service.networkinput/getPointerInputSocket")
            guard let path = response["socketPath"] as? String, let url = self.onTVHost(path) else {
                throw TVError.badResponse("no pointer socket")
            }
            let socket = self.session.webSocketTask(with: url)
            socket.resume()
            self.listen(socket)
            return socket
        }
        pointerSocket = task
        do {
            return try await task.value
        } catch {
            pointerSocket = nil
            throw error
        }
    }

    private func dropPointer() {
        guard let pointerSocket else { return }
        self.pointerSocket = nil
        Task { try? await pointerSocket.value.cancel(with: .goingAway, reason: nil) }
    }

    /// The TV hands out its own IP and the plain ws:// port in URLs. Point every URL at
    /// the configured host on the TLS port, so a hostname works and TLS trust stays
    /// limited to that host.
    private func onTVHost(_ string: String) -> URL? {
        guard var components = URLComponents(string: string) else { return nil }
        if components.scheme == "ws" || components.scheme == "wss" { components.scheme = "wss" } else { components.scheme = "https" }
        components.host = host
        components.port = Self.port
        return components.url
    }

    private func send(type: String, uri: String?, payload: JSON, timeout: Duration) async throws -> JSON {
        guard let socket else { throw TVError.notConnected }
        nextId += 1
        let id = "\(type)_\(nextId)"
        var message: JSON = ["id": id, "type": type, "payload": payload]
        if let uri { message["uri"] = uri }
        let text = String(decoding: try JSONSerialization.data(withJSONObject: message), as: UTF8.self)

        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self.resolve(id, with: .failure(TVError.timeout(uri ?? type)))
            }
            pending[id] = (continuation, timer)
            Task {
                do {
                    try await socket.send(.string(text))
                } catch {
                    self.resolve(id, with: .failure(error))
                }
            }
        }
    }

    private func listen(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            Task { await self.handle(result, from: task) }
        }
    }

    private func handle(_ result: Result<URLSessionWebSocketTask.Message, Error>, from task: URLSessionWebSocketTask) async {
        switch result {
        case .failure(let error) where task === socket:
            close(failing: error)
            onDisconnect?()
        case .failure:
            // The pointer socket closed; the next press opens a new one.
            if let pointerSocket, (try? await pointerSocket.value) === task { self.pointerSocket = nil }
        case .success(let message):
            guard task === socket else { return listen(task) }
            if case .string(let text) = message { route(text) }
            listen(task)
        }
    }

    private func route(_ text: String) {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? JSON,
              let id = json["id"] as? String else { return }
        let type = json["type"] as? String
        let payload = json["payload"] as? JSON ?? [:]

        if type == "error" {
            let reason = json["error"] as? String ?? "unknown error"
            let error: TVError = id.hasPrefix("register_") ? .pairingRejected(reason) : .tv(reason)
            resolve(id, with: .failure(error))
            return
        }
        // Registration first answers "response" (prompt shown), then "registered".
        if id.hasPrefix("register_") && type != "registered" { return }
        if payload["returnValue"] as? Bool == false {
            resolve(id, with: .failure(TVError.tv(payload["errorText"] as? String ?? "request failed")))
            return
        }
        resolve(id, with: .success(payload))
    }

    private func resolve(_ id: String, with result: Result<JSON, Error>) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timeout.cancel()
        entry.reply.resume(with: result)
    }

    private func close(failing error: Error) {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        dropPointer()
        let waiting = pending
        pending.removeAll()
        for entry in waiting.values {
            entry.timeout.cancel()
            entry.reply.resume(throwing: error)
        }
    }
}
