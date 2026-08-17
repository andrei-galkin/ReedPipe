import JavaScriptKit
import JavaScript
import Core

/// Owns the WebSocket connection, the in-memory session store, and the DOM
/// renderer, and wires them together. This is the one long-lived object for
/// the page — see AppRetain in App.swift for why something has to hold onto it.
final class SessionController {
    static let defaultWebSocketURL = "ws://127.0.0.1:8080/ws"

    private let store = SessionStore()
    private let renderer: SessionListRenderer
    private let statusElementID: String
    private let webSocketURL: String
    private var webSocketClient: WebSocketClient?

    init(statusElementID: String, containerID: String, webSocketURL: String = SessionController.defaultWebSocketURL) {
        self.statusElementID = statusElementID
        self.webSocketURL = webSocketURL
        self.renderer = SessionListRenderer(containerID: containerID)
    }

    /// Deliberately separate from init: building the WebSocketClient here
    /// (rather than during property initialization) avoids capturing `self`
    /// in a closure before every stored property is set.
    func start() {
        let client = WebSocketClient(
            url: webSocketURL,
            onMessage: { [weak self] text in self?.handleIncoming(text: text) },
            onStatusChange: { [weak self] status in self?.updateStatus(status) }
        )
        webSocketClient = client
        client.connect()
    }

    private func handleIncoming(text: String) {
        do {
            let json = JSObject.global.JSON.parse(text)
            let frame = try TrafficFrame.load(from: json)
            if store.upsert(frame) {
                renderer.appendRow(for: frame)
            } else {
                renderer.updateRow(for: frame)
            }
        } catch {
            // A malformed frame shouldn't take down the whole page — log and
            // move on to the next message.
            print("ReedPipe: failed to decode frame: \(error)")
        }
    }

    private func updateStatus(_ status: WebSocketClient.ConnectionStatus) {
        guard let element = JSHelper.byID(statusElementID) else { return }
        switch status {
        case .connecting:
            JSHelper.setText(element, "Connecting…")
        case .connected:
            JSHelper.setText(element, "Connected — live")
        case .disconnected:
            JSHelper.setText(element, "Disconnected — retrying…")
        }
    }
}
