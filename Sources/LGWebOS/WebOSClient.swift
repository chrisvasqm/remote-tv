import Foundation
import RemoteTVCore

/// Talks to an LG webOS TV over its local SSAP WebSocket API (wss, port 3001).
///
/// Pairing uses an unsigned manifest: recent firmware rejects the signed manifest that
/// third-party clients share ("403 Pairing rejected: blacklisted certificate detected"),
/// but still accepts an unsigned one after the user confirms the prompt on the TV.
public actor WebOSClient: TV {
    public typealias JSON = [String: Any]
    static let port = 3001
    private static let requestTimeout: Duration = .seconds(10)
    private static let pairingTimeout: Duration = .seconds(60)

    private let host: String
    private let keyStore: KeyStore
    nonisolated private let session: URLSession
    nonisolated private let trust: TVTrustDelegate
    private var socket: URLSessionWebSocketTask?
    private var pointerSocket: Task<URLSessionWebSocketTask, Error>?
    private var pending: [String: (reply: CheckedContinuation<JSON, Error>, timeout: Task<Void, Never>)] = [:]
    private var nextId = 0
    private var onDisconnect: (@Sendable () -> Void)?
    /// The live view's previous capture, downloading while the TV captures the next.
    private var pendingFrame: Task<Data, Error>?

    public init(host: String, keyStore: KeyStore) {
        self.host = host
        self.keyStore = keyStore
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        self.trust = TVTrustDelegate(host: host, port: Self.port, expectedPin: keyStore.pin(for: host))
        self.session = URLSession(
            configuration: configuration,
            delegate: trust,
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
            // Even with a stored key the TV may prompt again (pairing removed on the TV),
            // so always allow time to accept it.
            let response = try await send(type: "register", uri: nil, payload: payload, timeout: Self.pairingTimeout)
            guard let key = response["client-key"] as? String else {
                throw TVError.badResponse("registration without a client key")
            }
            if key != storedKey { keyStore.setKey(key, for: host) }
            if keyStore.pin(for: host) == nil, let pin = trust.observedPin {
                keyStore.setPin(pin, for: host)
                trust.pin(pin)
            }
        } catch {
            disconnect()
            throw trust.pinMismatch ? TVError.certificateChanged : error
        }
    }

    public func disconnect() {
        close(failing: TVError.notConnected)
    }

    /// Disconnects and releases the URL session. The client cannot be used afterwards.
    public func shutdown() {
        dropPendingFrame()
        disconnect()
        session.invalidateAndCancel()
    }

    /// Sends an SSAP request such as `ssap://audio/getVolume` and returns its payload.
    @discardableResult
    public func request(_ uri: String, _ payload: JSON = [:]) async throws -> JSON {
        try await send(type: "request", uri: uri, payload: payload, timeout: Self.requestTimeout)
    }

    /// Presses a remote button by its webOS name (UP, ENTER, BACK, HOME, MENU, ...).
    /// Long presses are not supported by the TV's pointer socket.
    public func press(button: String) async throws {
        try await pointer().send(.string("type:button\nname:\(button)\n\n"))
    }

    /// Captures the screen. Protected content (Netflix, HDMI, Live TV) comes back black.
    public func screenshot() async throws -> Data {
        try await download(capture())
    }

    /// Captures the next frame while the previous one downloads. The TV captures one
    /// frame at a time into the same file, so captures can't overlap each other, but a
    /// download can overlap the next capture: about 3 frames a second instead of 2.
    public func nextFrame() async throws -> Data? {
        let url = try await capture()
        let previous = pendingFrame
        pendingFrame = Task { try await download(url) }
        return try await previous?.value
    }

    public func dropPendingFrame() {
        pendingFrame?.cancel()
        pendingFrame = nil
    }

    /// Asks the TV to capture the screen and returns where to fetch the image.
    /// The TV captures one frame at a time and reuses the same file for each.
    private func capture() async throws -> URL {
        let response = try await request("ssap://tv/executeOneShot")
        guard let uri = response["imageUri"] as? String, let url = onTVHost(uri) else {
            throw TVError.badResponse("screenshot without an image address")
        }
        return url
    }

    /// Fetches a captured image. Runs outside the actor so it can overlap the next capture.
    private nonisolated func download(_ url: URL) async throws -> Data {
        do {
            return try await session.data(from: url).0
        } catch URLError.timedOut {
            throw TVError.timeout(url.path)
        }
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
            if pointerSocket == task { pointerSocket = nil }
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
    /// limited to that host. Internal, not private, so tests can check it.
    func onTVHost(_ string: String) -> URL? {
        guard var components = URLComponents(string: string) else { return nil }
        components.scheme = components.scheme == "ws" || components.scheme == "wss" ? "wss" : "https"
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
        guard let text = String(bytes: try JSONSerialization.data(withJSONObject: message), encoding: .utf8) else {
            throw TVError.badResponse("request could not be encoded")
        }

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

    private func handle(
        _ result: Result<URLSessionWebSocketTask.Message, Error>, from task: URLSessionWebSocketTask
    ) async {
        switch result {
        case .failure(let error) where task === socket:
            close(failing: error)
            onDisconnect?()
        case .failure:
            // The pointer socket closed; the next press opens a new one.
            if let pointerSocket, (try? await pointerSocket.value) === task { self.pointerSocket = nil }
        case .success(let message):
            if task === socket, case .string(let text) = message { route(text) }
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
