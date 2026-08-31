public enum RawResponseFormatter {
    /// Reconstructs the captured HTTP message using the wire-format CRLF
    /// separators. Binary bodies remain Base64 because capture deliberately
    /// stores them in a display-safe form.
    public static func format(_ response: CapturedResponse) -> String {
        var lines: [String] = [
            "\(response.httpVersion) \(response.statusCode) \(response.reason)"
        ]
        lines.reserveCapacity(response.headers.count + 1)

        for header: CapturedHeader in response.headers {
            lines.append("\(header.name): \(header.value)")
        }

        let head: String = lines.joined(separator: "\r\n")
        guard let body: String = response.body else {
            return head + "\r\n\r\n"
        }
        return head + "\r\n\r\n" + body
    }
}
