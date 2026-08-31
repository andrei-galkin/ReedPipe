import JavaScriptKit
import Core

/// Errors that can occur during frame decoding.
enum FrameDecodingError: Error, CustomStringConvertible {
    case invalidType
    case missingValue
    case parseFailed
    
    var description: String {
        switch self {
        case .invalidType:
            return "Invalid type in JSON"
        case .missingValue:
            return "Missing required value in JSON"
        case .parseFailed:
            return "Failed to parse JSON"
        }
    }
}

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
            guard let json = JSObject.global.JSON.parse(text).object else {
                throw FrameDecodingError.parseFailed
            }
            
            let frame = try buildTrafficFrame(from: json)
            
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
    
    private func buildTrafficFrame(from json: JSObject) throws -> TrafficFrame {
        let id = try getString(json["id"])
        let timestamp = try getString(json["timestamp"])
        let request = try buildCapturedRequest(json["request"])
        let response = try buildCapturedResponseOptional(json["response"])
        let durationMs = try getDoubleOptional(json["durationMs"])
        let error = try getStringOptional(json["error"])
        
        return TrafficFrame(
            id: id,
            timestamp: timestamp,
            request: request,
            response: response,
            durationMs: durationMs,
            error: error
        )
    }
    
    private func buildCapturedRequest(_ json: JSValue) throws -> CapturedRequest {
        guard let obj = json.object else {
            throw FrameDecodingError.invalidType
        }
        
        let method = try getString(obj["method"])
        let url = try getString(obj["url"])
        let headers = try buildHeaders(obj["headers"])
        let body = try getStringOptional(obj["body"])
        let bodyIsBase64 = try getBool(obj["bodyIsBase64"])
        
        return CapturedRequest(method: method, url: url, headers: headers, body: body, bodyIsBase64: bodyIsBase64)
    }
    
    private func buildCapturedResponseOptional(_ json: JSValue) throws -> CapturedResponse? {
        if json.isUndefined || json.isNull {
            return nil
        }
        
        guard let obj = json.object else {
            return nil
        }
        
        let httpVersion = try getString(obj["httpVersion"])
        let statusCode = try getInt(obj["statusCode"])
        let reason = try getString(obj["reason"])
        let headers = try buildHeaders(obj["headers"])
        let body = try getStringOptional(obj["body"])
        let bodyIsBase64 = try getBool(obj["bodyIsBase64"])
        
        return CapturedResponse(
            httpVersion: httpVersion,
            statusCode: statusCode,
            reason: reason,
            headers: headers,
            body: body,
            bodyIsBase64: bodyIsBase64
        )
    }
    
    private func buildHeaders(_ json: JSValue) throws -> [CapturedHeader] {
        guard let array = json.object else {
            return []
        }
        
        var headers: [CapturedHeader] = []
        var index = 0
        while let headerValue = array[index].object {
            let name = try getString(headerValue["name"])
            let value = try getString(headerValue["value"])
            headers.append(CapturedHeader(name: name, value: value))
            index += 1
        }
        
        return headers
    }
    
    private func getString(_ value: JSValue) throws -> String {
        guard let str = value.string else {
            throw FrameDecodingError.missingValue
        }
        return str
    }
    
    private func getStringOptional(_ value: JSValue) throws -> String? {
        if value.isUndefined || value.isNull {
            return nil
        }
        return try getString(value)
    }
    
    private func getInt(_ value: JSValue) throws -> Int {
        guard let num = value.number, let int = Int(exactly: num) else {
            throw FrameDecodingError.invalidType
        }
        return int
    }
    
    private func getDouble(_ value: JSValue) throws -> Double {
        guard let num = value.number else {
            throw FrameDecodingError.invalidType
        }
        return num
    }
    
    private func getDoubleOptional(_ value: JSValue) throws -> Double? {
        if value.isUndefined || value.isNull {
            return nil
        }
        return try getDouble(value)
    }
    
    private func getBool(_ value: JSValue) throws -> Bool {
        guard let bool = value.boolean else {
            throw FrameDecodingError.invalidType
        }
        return bool
    }

    private func updateStatus(_ status: WebSocketClient.ConnectionStatus) {
        guard let element = JSHelper.byID(statusElementID) else { return }
        switch status {
        case .connecting:
            JSHelper.setText(element, "Connecting…")
            JSHelper.setTextColor(element, "#555")
        case .connected:
            JSHelper.setText(element, "Connected — live")
            JSHelper.setTextColor(element, "#188038")
        case .disconnected:
            JSHelper.setText(element, "Disconnected — retrying…")
            JSHelper.setTextColor(element, "#555")
        }
    }
}
