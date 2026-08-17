import Foundation

/// Native-only JSON and timestamp formatting. The browser uses JavaScript's
/// JSON.parse plus JavaScriptKit's JSValueDecoder, avoiding Foundation in Wasm.
enum FrameCoding {
    private static let timestampFormatter = ISO8601DateFormatter()

    static func makeEncoder() -> JSONEncoder {
        JSONEncoder()
    }

    static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }
}
