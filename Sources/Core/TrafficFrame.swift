import Foundation

/// One full request/response exchange captured by the proxy. This is the unit
/// serialized to JSON and pushed to the browser frontend over the WebSocket
/// bridge (Week 3), and decoded back into this same type on the Frontend side.
public struct TrafficFrame: Codable, Equatable {
    public let id: String
    public let timestamp: Date
    public let request: CapturedRequest
    public var response: CapturedResponse?
    /// Wall-clock duration from request start to response completion, in milliseconds.
    public var durationMs: Double?
    /// Set when the backend connection failed or errored before a response was
    /// received (connect failure, reset mid-response, etc). `response` will be
    /// nil in that case. A frame with both `response` and `error` nil means the
    /// exchange is still in flight.
    public var error: String?

    public init(id: String, timestamp: Date, request: CapturedRequest, response: CapturedResponse?,
                durationMs: Double?, error: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.request = request
        self.response = response
        self.durationMs = durationMs
        self.error = error
    }
}