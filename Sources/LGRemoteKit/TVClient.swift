import Foundation

public enum TVError: LocalizedError {
    case notConnected
    case pairingRejected(String)
    case timeout(String)
    case tv(String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to the TV."
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

    public let host: String
    private let keyStore: KeyStore
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var pointerSocket: URLSessionWebSocketTask?
    private var pending: [String: CheckedContinuation<JSON, Error>] = [:]
    private var nextId = 0

    public init(host: String, keyStore: KeyStore) {
        self.host = host
        self.keyStore = keyStore
        self.session = URLSession(
            configuration: .ephemeral,
            delegate: TVTrustDelegate(host: host),
            delegateQueue: nil
        )
    }

    public var isConnected: Bool { socket != nil }

    /// Opens the socket and registers. Without a stored key the TV shows a prompt,
    /// so this can take as long as the user needs to accept it (up to `pairingTimeout`).
    public func connect(pairingTimeout: TimeInterval = 60) async throws {
        disconnect()
        guard let url = URL(string: "wss://\(host):3001") else { throw TVError.notConnected }
        let task = session.webSocketTask(with: url)
        task.resume()
        socket = task
        listen(task)

        let storedKey = keyStore.key(for: host)
        var payload: JSON = ["forcePairing": false, "pairingType": "PROMPT", "manifest": Manifest.unsigned]
        if let storedKey { payload["client-key"] = storedKey }
        let timeout = storedKey == nil ? pairingTimeout : 10
        do {
            let response = try await send(type: "register", uri: nil, payload: payload, timeout: timeout)
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
        socket?.cancel(with: .goingAway, reason: nil)
        pointerSocket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        pointerSocket = nil
        failAll(TVError.notConnected)
    }

    /// Sends an SSAP request such as `ssap://audio/getVolume` and returns its payload.
    @discardableResult
    public func request(_ uri: String, _ payload: JSON = [:], timeout: TimeInterval = 10) async throws -> JSON {
        try await send(type: "request", uri: uri, payload: payload, timeout: timeout)
    }

    /// Presses a remote button (UP, DOWN, LEFT, RIGHT, ENTER, BACK, HOME, MENU, ...).
    /// Long presses are not supported by the TV's pointer socket.
    public func press(_ button: String) async throws {
        let pointer = try await pointer()
        try await pointer.send(.string("type:button\nname:\(button)\n\n"))
    }

    /// Captures the screen. Protected content (Netflix, HDMI, Live TV) comes back black.
    public func screenshot() async throws -> Data {
        let response = try await request("ssap://tv/executeOneShot")
        guard let uri = response["imageUri"] as? String, let url = URL(string: uri), url.host == host else {
            throw TVError.badResponse("screenshot without an image address")
        }
        let (data, _) = try await session.data(from: url)
        return data
    }

    // MARK: - Socket plumbing

    private func pointer() async throws -> URLSessionWebSocketTask {
        if let pointerSocket { return pointerSocket }
        let response = try await request("ssap://com.webos.service.networkinput/getPointerInputSocket")
        guard let path = response["socketPath"] as? String else {
            throw TVError.badResponse("no pointer socket")
        }
        // The TV hands out the plain ws:// port; the same path works on the TLS port.
        let securePath = path
            .replacingOccurrences(of: "ws://", with: "wss://")
            .replacingOccurrences(of: ":3000/", with: ":3001/")
        guard let url = URL(string: securePath), url.host == host else {
            throw TVError.badResponse("pointer socket on another host")
        }
        let task = session.webSocketTask(with: url)
        task.resume()
        pointerSocket = task
        return task
    }

    private func send(type: String, uri: String?, payload: JSON, timeout: TimeInterval) async throws -> JSON {
        guard let socket else { throw TVError.notConnected }
        nextId += 1
        let id = "\(type)_\(nextId)"
        var message: JSON = ["id": id, "type": type, "payload": payload]
        if let uri { message["uri"] = uri }
        let data = try JSONSerialization.data(withJSONObject: message)
        let text = String(decoding: data, as: UTF8.self)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    try await socket.send(.string(text))
                } catch {
                    self.resolve(id, with: .failure(error))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.resolve(id, with: .failure(TVError.timeout(uri ?? type)))
            }
        }
    }

    private func listen(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            Task { await self.handle(result, from: task) }
        }
    }

    private func handle(_ result: Result<URLSessionWebSocketTask.Message, Error>, from task: URLSessionWebSocketTask) {
        guard task === socket else { return }
        switch result {
        case .failure(let error):
            socket = nil
            pointerSocket?.cancel(with: .goingAway, reason: nil)
            pointerSocket = nil
            failAll(error)
        case .success(let message):
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
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(with: result)
    }

    private func failAll(_ error: Error) {
        let waiting = pending
        pending.removeAll()
        waiting.values.forEach { $0.resume(throwing: error) }
    }
}
