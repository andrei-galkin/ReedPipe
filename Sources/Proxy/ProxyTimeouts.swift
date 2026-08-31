import NIO

enum ProxyTimeouts {
    static let connect: TimeAmount = .seconds(10)
    static let upstreamRead: TimeAmount = .seconds(12)
}
