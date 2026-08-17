import JavaScript
import Core

// JSS mappings are kept in the browser target so Core remains independent of
// JavaScriptKit and continues to compile for both the proxy and WebAssembly.

extension CapturedHeader {
    public enum ObjectKey: JSString {
        case name
        case value
    }
}

extension CapturedHeader: JavaScriptDecodable {
    public init(from js: borrowing JavaScriptDecoder<ObjectKey>) throws {
        self.init(
            name: try js[.name].decode(),
            value: try js[.value].decode()
        )
    }
}

extension CapturedRequest {
    public enum ObjectKey: JSString {
        case method
        case url
        case headers
        case body
        case bodyIsBase64
    }
}

extension CapturedRequest: JavaScriptDecodable {
    public init(from js: borrowing JavaScriptDecoder<ObjectKey>) throws {
        self.init(
            method: try js[.method].decode(),
            url: try js[.url].decode(),
            headers: try js[.headers].decode(),
            body: try js[.body]?.decode(),
            bodyIsBase64: try js[.bodyIsBase64].decode()
        )
    }
}

extension CapturedResponse {
    public enum ObjectKey: JSString {
        case statusCode
        case reason
        case headers
        case body
        case bodyIsBase64
    }
}

extension CapturedResponse: JavaScriptDecodable {
    public init(from js: borrowing JavaScriptDecoder<ObjectKey>) throws {
        self.init(
            statusCode: try js[.statusCode].decode(),
            reason: try js[.reason].decode(),
            headers: try js[.headers].decode(),
            body: try js[.body]?.decode(),
            bodyIsBase64: try js[.bodyIsBase64].decode()
        )
    }
}

extension TrafficFrame {
    public enum ObjectKey: JSString {
        case id
        case timestamp
        case request
        case response
        case durationMs
        case error
    }
}

extension TrafficFrame: JavaScriptDecodable {
    public init(from js: borrowing JavaScriptDecoder<ObjectKey>) throws {
        self.init(
            id: try js[.id].decode(),
            timestamp: try js[.timestamp].decode(),
            request: try js[.request].decode(),
            response: try js[.response]?.decode(),
            durationMs: try js[.durationMs]?.decode(),
            error: try js[.error]?.decode()
        )
    }
}
