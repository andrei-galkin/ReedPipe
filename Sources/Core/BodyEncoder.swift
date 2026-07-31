import Foundation

public enum BodyEncoder {
    /// Turn raw bytes into a displayable string, preferring UTF-8 and falling
    /// back to base64 for binary payloads.
    public static func encode(_ bytes: [UInt8]) -> (text: String?, isBase64: Bool) {
        guard !bytes.isEmpty else { return (nil, false) }
        if let str = String(bytes: bytes, encoding: .utf8) {
            return (str, false)
        }
        return (Data(bytes).base64EncodedString(), true)
    }
}
