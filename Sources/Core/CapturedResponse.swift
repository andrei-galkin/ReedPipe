public struct CapturedResponse: Equatable {
    public let httpVersion: String
    public let statusCode: Int
    public let reason: String
    public let headers: [CapturedHeader]
    public let body: String?
    public let bodyIsBase64: Bool

    public init(
        httpVersion: String,
        statusCode: Int,
        reason: String,
        headers: [CapturedHeader],
        body: String?,
        bodyIsBase64: Bool
    ) {
        self.httpVersion = httpVersion
        self.statusCode = statusCode
        self.reason = reason
        self.headers = headers
        self.body = body
        self.bodyIsBase64 = bodyIsBase64
    }
}

#if !os(WASI) && !hasFeature(Embedded)
extension CapturedResponse: Codable {}
#endif
