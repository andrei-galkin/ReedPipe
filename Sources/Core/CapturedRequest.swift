public struct CapturedRequest: Equatable {
    public let method: String
    public let url: String
    public let headers: [CapturedHeader]
    /// Body captured as UTF-8 text when possible, base64 otherwise. Kept simple for Phase 1.
    public let body: String?
    public let bodyIsBase64: Bool

    public init(method: String, url: String, headers: [CapturedHeader], body: String?, bodyIsBase64: Bool) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.bodyIsBase64 = bodyIsBase64
    }
}

#if !hasFeature(Embedded)
extension CapturedRequest: Codable {}
#endif
