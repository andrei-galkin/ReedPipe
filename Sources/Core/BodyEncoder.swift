public enum BodyEncoder {
    /// Turn raw bytes into a displayable string, preferring UTF-8 and falling
    /// back to base64 for binary payloads.
    public static func encode(_ bytes: [UInt8]) -> (text: String?, isBase64: Bool) {
        guard !bytes.isEmpty else { return (nil, false) }
        if let str = String(validating: bytes, as: UTF8.self) {
            return (str, false)
        }
        return (encodeBase64(bytes), true)
    }

    private static func encodeBase64(_ bytes: [UInt8]) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
        var encoded: [UInt8] = []
        encoded.reserveCapacity(((bytes.count + 2) / 3) * 4)

        var index = 0
        while index < bytes.count {
            let remaining = bytes.count - index
            let first = UInt32(bytes[index])
            let second = remaining > 1 ? UInt32(bytes[index + 1]) : 0
            let third = remaining > 2 ? UInt32(bytes[index + 2]) : 0
            let value = (first << 16) | (second << 8) | third

            encoded.append(alphabet[Int((value >> 18) & 0x3f)])
            encoded.append(alphabet[Int((value >> 12) & 0x3f)])
            encoded.append(remaining > 1 ? alphabet[Int((value >> 6) & 0x3f)] : 61)
            encoded.append(remaining > 2 ? alphabet[Int(value & 0x3f)] : 61)
            index += 3
        }

        return String(decoding: encoded, as: UTF8.self)
    }
}
