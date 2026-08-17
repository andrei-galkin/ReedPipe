/// A single captured HTTP header as a plain name/value pair (Codable-friendly,
/// unlike NIOHTTP1.HTTPHeaders which isn't and which the Frontend target
/// doesn't depend on anyway).
public struct CapturedHeader: Equatable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

#if !hasFeature(Embedded)
extension CapturedHeader: Codable {}
#endif
