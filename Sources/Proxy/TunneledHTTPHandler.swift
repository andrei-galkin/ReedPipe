import Foundation
import NIO
import NIOHTTP1
import NIOSSL
import Core

/// The HTTPS counterpart to FrontendHandler: sits inside a CONNECT tunnel,
/// after TLS has been terminated, and sees the same kind of
/// HTTPServerRequestPart stream FrontendHandler does — except requests here
/// arrive in origin-form (`GET /path HTTP/1.1` + a `Host` header) rather than
/// absolute-form, since that's what a real HTTPS client sends once a tunnel
/// is established. `tunnelHost`/`tunnelPort` (from the original CONNECT
/// request) are used to reconstruct a full `https://...` URL for capture,
/// and to open the real outbound connection to the origin over TLS.
final class TunneledHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let tunnelHost: String
    private let tunnelPort: Int

    private var requestHead: HTTPRequestHead?
    private var requestBodyBytes: [UInt8] = []
    private var startTime: Date?

    init(tunnelHost: String, tunnelPort: Int) {
        self.tunnelHost = tunnelHost
        self.tunnelPort = tunnelPort
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
            requestBodyBytes.removeAll(keepingCapacity: true)
            startTime = Date()

        case .body(let buffer):
            requestBodyBytes.append(contentsOf: buffer.readableBytesView)

        case .end:
            guard let head = requestHead else { return }
            forward(head: head, body: requestBodyBytes, clientChannel: context.channel, startTime: startTime ?? Date())
        }
    }

    private func forward(head: HTTPRequestHead, body: [UInt8], clientChannel: Channel, startTime: Date) {
        // Requests inside the tunnel are origin-form; reconstruct the full
        // URL from the Host header (falling back to the CONNECT target if
        // the request is somehow missing one) purely for capture purposes.
        let hostHeader = head.headers.first(name: "Host") ?? tunnelHost
        let fullURL = "https://\(hostHeader)\(head.uri)"

        var forwardHeaders = head.headers
        forwardHeaders.replaceOrAdd(name: "Connection", value: "close")

        var originHead = HTTPRequestHead(version: head.version, method: head.method, uri: head.uri)
        originHead.headers = forwardHeaders

        let capturedHeaders = head.headers.map { CapturedHeader(name: $0.name, value: $0.value) }
        let (bodyText, isBase64) = BodyEncoder.encode(body)
        let capturedRequest = CapturedRequest(
            method: head.method.rawValue,
            url: fullURL,
            headers: capturedHeaders,
            body: bodyText,
            bodyIsBase64: isBase64
        )
        let transaction: CaptureTransaction = .init(request: capturedRequest, startTime: startTime)

        let bootstrap: ClientBootstrap = ClientBootstrap(group: clientChannel.eventLoop.next())
            .connectTimeout(ProxyTimeouts.connect)
            .channelInitializer { channel in
                do {
                    let tlsConfig: TLSConfiguration = .makeClientConfiguration()
                    let sslContext: NIOSSLContext = try .init(configuration: tlsConfig)
                    let sslHandler: NIOSSLClientHandler = try .init(
                        context: sslContext,
                        serverHostname: self.tunnelHost
                    )
                    return channel.pipeline.addHandler(sslHandler).flatMap {
                        channel.pipeline.addHTTPClientHandlers()
                    }.flatMap {
                        do {
                            try channel.pipeline.syncOperations.addHandler(
                                IdleStateHandler(readTimeout: ProxyTimeouts.upstreamRead)
                            )
                            return channel.eventLoop.makeSucceededFuture(())
                        } catch {
                            return channel.eventLoop.makeFailedFuture(error)
                        }
                    }.flatMap {
                        channel.pipeline.addHandler(BackendHandler(
                            requestHead: originHead,
                            requestBody: body,
                            transaction: transaction,
                            clientChannel: clientChannel
                        ))
                    }
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }

        bootstrap.connect(host: tunnelHost, port: tunnelPort).whenFailure { [weak self] error in
            guard let self else { return }
            guard transaction.emit(error: error) else { return }
            self.writeErrorResponse(channel: clientChannel, message: "Could not connect to \(self.tunnelHost):\(self.tunnelPort) — \(error)")
        }
    }

    private func writeErrorResponse(channel: Channel, message: String) {
        var buffer = channel.allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)

        var head = HTTPResponseHead(version: .http1_1, status: .badGateway)
        head.headers.replaceOrAdd(name: "Content-Length", value: "\(buffer.readableBytes)")
        head.headers.replaceOrAdd(name: "Connection", value: "close")

        channel.writeAndFlush(HTTPServerResponsePart.head(head), promise: nil)
        channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
        channel.writeAndFlush(HTTPServerResponsePart.end(nil)).whenComplete { _ in
            channel.close(promise: nil)
        }
    }
}
