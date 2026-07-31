import JavaScriptKit

/// Thin wrapper around the browser's WebSocket API, connecting to the
/// proxy's live frame feed (`ws://host:port/ws`). Reconnects automatically
/// with backoff on close/error, so a proxy restart doesn't require a page
/// reload — it'll just resume once the proxy comes back.
final class WebSocketClient {
    enum ConnectionStatus {
        case connecting
        case connected
        case disconnected
    }

    private let url: String
    private let onMessage: (String) -> Void
    private let onStatusChange: (ConnectionStatus) -> Void

    private var reconnectDelayMs: Double = 1000
    private let maxReconnectDelayMs: Double = 10_000
    /// Held as a property (not discarded) so it isn't deallocated — and the
    /// pending timer cancelled — before it fires.
    private var reconnectTimer: JSTimer?

    init(url: String, onMessage: @escaping (String) -> Void, onStatusChange: @escaping (ConnectionStatus) -> Void) {
        self.url = url
        self.onMessage = onMessage
        self.onStatusChange = onStatusChange
    }

    func connect() {
        onStatusChange(.connecting)

        guard let socket = JSHelper.newWebSocket(url) else {
            print("ReedPipe: WebSocket API is not available in this environment")
            return
        }

        socket.onopen = .object(JSClosure { [weak self] _ in
            self?.reconnectDelayMs = 1000
            self?.onStatusChange(.connected)
            return .undefined
        })

        socket.onmessage = .object(JSClosure { [weak self] arguments in
            guard let text = JSHelper.messageText(from: arguments) else { return .undefined }
            self?.onMessage(text)
            return .undefined
        })

        socket.onclose = .object(JSClosure { [weak self] _ in
            self?.scheduleReconnect()
            return .undefined
        })

        // A failed connection attempt fires `error` before `close`, so this
        // can double up with the onclose handler above for the same failure.
        // scheduleReconnect() overwrites `reconnectTimer` either way, so at
        // worst there's a redundant scheduling, not a correctness problem.
        socket.onerror = .object(JSClosure { [weak self] _ in
            self?.scheduleReconnect()
            return .undefined
        })
    }

    private func scheduleReconnect() {
        onStatusChange(.disconnected)
        let delay = reconnectDelayMs
        reconnectDelayMs = min(reconnectDelayMs * 2, maxReconnectDelayMs)
        reconnectTimer = JSTimer(millisecondsDelay: delay, isRepeating: false) { [weak self] in
            self?.connect()
        }
    }
}