import Foundation

/// Shared JSON encoder/decoder config so the Proxy and Frontend agree on
/// wire format (ISO 8601 dates) without duplicating the setup.
public enum FrameCoding {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
