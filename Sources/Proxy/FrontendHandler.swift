import Foundation
import NIO
import NIOHTTP1
import NIOSSL
import Core
import Foundation
import NIO
import NIOHTTP1
import NIOSSL
import Core

/// Handles the client-facing side of a proxy connection.
//
/// Plain HTTP: the client (e.g. `curl -x http://localhost:8080 ...`) sends a
/// request with an absolute-form URI in the request line
/// (`GET http://example.com/path HTTP/1.1`). We buffer the full request, open a
/// fresh connection to the real destination, replay the request there, and once
/// the response comes back we write it to the client and emit a captured Frame.
//
/// HTTPS (CONNECT): the client instead sends `CONNECT host:port HTTP/1.1`. We
/// acknowledge the tunnel, then terminate TLS ourselves using a certificate
/// minted by CertificateAuthority, so everything sent through the now-decrypted
/// tunnel can be parsed and captured the same way as plain HTTP — see
/// TunneledHTTPHandler, which takes over once the handshake completes.
//
/// Bodies are fully buffered rather than streamed — a deliberate simplification
/// for a debugging tool: trivial to verify correctness, at the cost of not being
/// ideal for huge payloads / streaming responses. Revisit if that matters later.
final class FrontendHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let certificateAuthority: CertificateAuthority?
    private let bypassManager: BypassManager?

    private var requestHead: HTTPRequestHead?
    private var requestBodyBytes: [UInt8] = []
    private var startTime: Date?

    init(certificateAuthority: CertificateAuthority?, bypassManager: BypassManager?) {
        self.certificateAuthority = certificateAuthority
        self.bypassManager = bypassManager
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            if head.method == .CONNECT {
                handleConnect(head: head, context: context)
                return
            }
            requestHead = head
            requestBodyBytes.removeAll(keepingCapacity: true)
            startTime = Date()

        case .body(let buffer):
            requestBodyBytes.append(contentsOf: buffer.readableBytesView)

        case .end:
            guard let head = requestHead else {
                writeSimpleError(channel: context.channel, status: .badRequest, message: "No request head")
                return
            }
            forward(head: head, body: requestBodyBytes, clientChannel: context.channel, startTime: startTime ?? Date())
        }
    }

    private func forward(head: HTTPRequestHead, body: [UInt8], clientChannel: Channel, startTime: Date) {
        guard let url = URL(string: head.uri), let host = url.host else {
            writeSimpleError(channel: clientChannel, status: .badRequest,
                             message: "Phase 1 proxy requires an absolute-form URI, e.g. curl -x http://localhost:8080 http://example.com")
            return
        }
        let port = url.port ?? 80

        var originPath = url.path.isEmpty ? "/" : url.path
        if let query = url.query {
            originPath += "?\(query)"
        }

        var forwardHeaders = head.headers
        forwardHeaders.replaceOrAdd(name: "Host", value: port == 80 ? host : "\(host):\(port)")
        forwardHeaders.remove(name: "Proxy-Connection")
        forwardHeaders.replaceOrAdd(name: "Connection", value: "close")

        var originHead = HTTPRequestHead(version: head.version, method: head.method, uri: originPath)
        originHead.headers = forwardHeaders

        let capturedHeaders = head.headers.map { CapturedHeader(name: $0.name, value: $0.value) }
        let (bodyText, isBase64) = BodyEncoder.encode(body)
        let capturedRequest = CapturedRequest(
            method: head.method.rawValue,
            url: head.uri,
            headers: capturedHeaders,
            body: bodyText,
            bodyIsBase64: isBase64
        )

        let bootstrap = ClientBootstrap(group: clientChannel.eventLoop.next())
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(BackendHandler(
                        requestHead: originHead,
                        requestBody: body,
                        capturedRequest: capturedRequest,
                        clientChannel: clientChannel,
                        startTime: startTime
                    ))
                }
            }

        bootstrap.connect(host: host, port: port).whenFailure { error in
            self.writeSimpleError(channel: clientChannel, status: .badGateway,
                                   message: "Could not connect to \(host):\(port) — \(error)")
        }
    }

    // MARK: - CONNECT / HTTPS interception

    private func handleConnect(head: HTTPRequestHead, context: ChannelHandlerContext) {
        guard certificateAuthority != nil else {
            writeSimpleError(channel: context.channel, status: .badGateway,
                              message: "HTTPS interception isn't configured on this proxy")
            return
        }

        // CONNECT's target is "host:port" (e.g. "example.com:443"), not a URL.
        let target = head.uri
        let components = target.split(separator: ":", maxSplits: 1)
        guard let hostPart = components.first, !hostPart.isEmpty else {
            writeSimpleError(channel: context.channel, status: .badRequest, message: "Malformed CONNECT target: \(target)")
            return
        }
        let host = String(hostPart)
        let port = components.count > 1 ? (Int(components[1]) ?? 443) : 443

        // Acknowledge the tunnel in plaintext first — the client expects this
        // response before it starts sending TLS bytes (its ClientHello).
        let established = HTTPResponseHead(version: .http1_1, status: .custom(code: 200, reasonPhrase: "Connection Established"))
        context.writeAndFlush(wrapOutboundOut(.head(established)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { [weak self] result in
            guard let self, case .success = result else { return }
            if let bypass = self.bypassManager, bypass.contains(host) {
                self.setupRawTunnel(host: host, port: port, context: context)
            } else {
                self.upgradeToTLS(host: host, port: port, context: context)
            }
        }
    }

    /// Set up a raw TCP tunnel (no TLS termination) between client and origin.
    private func setupRawTunnel(host: String, port: Int, context: ChannelHandlerContext) {
        let channel = context.channel

        // remove HTTP handlers the same way upgradeToTLS does
        channel.pipeline.removeHandler(context: context)
            .flatMap { channel.pipeline.handler(type: ByteToMessageHandler<HTTPRequestDecoder>.self) }
            .flatMap { channel.pipeline.removeHandler($0) }
            .flatMap { channel.pipeline.handler(type: HTTPResponseEncoder.self) }
            .flatMap { channel.pipeline.removeHandler($0) }
            .whenComplete { _ in
                let clientChannel = channel
                let bootstrap = ClientBootstrap(group: clientChannel.eventLoop)
                    .channelInitializer { outbound in
                        // nothing special on outbound pipeline; raw bytes
                        outbound.eventLoop.makeSucceededFuture(() as Void)
                    }

                bootstrap.connect(host: host, port: port).whenComplete { result in
                    switch result {
                    case .failure:
                        clientChannel.close(promise: nil)
                    case .success(let outboundChannel):
                        // add relay handlers to both pipelines
                        do {
                            try clientChannel.pipeline.addHandler(RelayHandler(peer: outboundChannel)).wait()
                            try outboundChannel.pipeline.addHandler(RelayHandler(peer: clientChannel)).wait()
                        } catch {
                            clientChannel.close(promise: nil)
                            outboundChannel.close(promise: nil)
                        }
                    }
                }
            }
    }

    /// Swaps this connection's pipeline from plaintext-HTTP to TLS-terminating:
    /// removes this handler and the HTTP/1.1 codec added by
    /// `configureHTTPServerPipeline`, adds an NIOSSLServerHandler using a
    /// certificate covering `host`, and once that's in place adds a fresh
    /// HTTP/1.1 codec + TunneledHTTPHandler to parse the now-decrypted traffic.
    private func upgradeToTLS(host: String, port: Int, context: ChannelHandlerContext) {
        let channel = context.channel
        guard let certificateAuthority else {
            channel.close(promise: nil)
            return
        }

        let sslContext: NIOSSLContext
        do {
            sslContext = try certificateAuthority.context(for: host)
        } catch {
            channel.close(promise: nil)
            return
        }
        let sslHandler = NIOSSLServerHandler(context: sslContext)

        channel.pipeline.removeHandler(context: context)
            .flatMap { channel.pipeline.handler(type: ByteToMessageHandler<HTTPRequestDecoder>.self) }
            .flatMap { channel.pipeline.removeHandler($0) }
            .flatMap { channel.pipeline.handler(type: HTTPResponseEncoder.self) }
            .flatMap { channel.pipeline.removeHandler($0) }
            .flatMap { channel.pipeline.addHandler(sslHandler) }
            .flatMap { channel.pipeline.addHandler(HTTPResponseEncoder()) }
            .flatMap { channel.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder())) }
            .flatMap { channel.pipeline.addHandler(TunneledHTTPHandler(tunnelHost: host, tunnelPort: port)) }
            .whenFailure { _ in
                channel.close(promise: nil)
            }
    }

    private func writeSimpleError(channel: Channel, status: HTTPResponseStatus, message: String) {
        var buffer = channel.allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)

        var head = HTTPResponseHead(version: .http1_1, status: status)
        head.headers.replaceOrAdd(name: "Content-Length", value: "\(buffer.readableBytes)")
        head.headers.replaceOrAdd(name: "Connection", value: "close")

        channel.writeAndFlush(HTTPServerResponsePart.head(head), promise: nil)
        channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
        channel.writeAndFlush(HTTPServerResponsePart.end(nil)).whenComplete { _ in
            channel.close(promise: nil)
        }
    }
}