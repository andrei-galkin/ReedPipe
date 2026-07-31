import Foundation
import NIO
import NIOHTTP1
import NIOWebSocket
import Core

/// Bootstraps the client-facing HTTP server. Kept as its own type (rather than
/// inlined in Main.swift) so the WebSocket upgrade path added here shares the
/// same childChannelInitializer as the proxy traffic path.
final class ProxyServer {
    private let group: EventLoopGroup
    private let certificateAuthority: CertificateAuthority
    private let bypassManager: BypassManager

    /// Path frontend clients connect to for the live frame feed, e.g.
    /// ws://127.0.0.1:8080/ws. Proxied traffic (absolute-form requests like
    /// `GET http://example.com/ HTTP/1.1`) never matches this, so both flows
    /// coexist on the same port.
    static let webSocketPath = "/ws"

    init(group: EventLoopGroup, certificateAuthority: CertificateAuthority, bypassManager: BypassManager) {
        self.group = group
        self.certificateAuthority = certificateAuthority
        self.bypassManager = bypassManager
    }

    func start(host: String, port: Int) -> EventLoopFuture<Channel> {
        // withPipeliningAssistance/withErrorHandling/withOutboundHeaderValidation
        // are all explicitly disabled here. This isn't just trimming unused
        // features: FrontendHandler.upgradeToTLS (for CONNECT/HTTPS) removes
        // exactly two handlers — the HTTP encoder and decoder — assuming
        // that's everything configureHTTPServerPipeline added below it. Any
        // of those three left enabled inserts an extra handler into the
        // pipeline that upgradeToTLS doesn't know about, which would end up
        // in the wrong position (appended after the newly-added TLS/codec
        // stack) once the swap happens — breaking HTTPS interception. If
        // pipelining or NIO's automatic error responses are needed later,
        // upgradeToTLS's removal list needs to grow to match.
        let wsUpgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, head in
                guard head.uri == ProxyServer.webSocketPath else {
                    return channel.eventLoop.makeSucceededFuture(nil)
                }
                return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { channel, _ in
                channel.pipeline.addHandler(WebSocketHandler())
            }
        )

        let upgradeConfig: NIOHTTPServerUpgradeConfiguration = (
            upgraders: [wsUpgrader],
            completionHandler: { _ in }
        )

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [certificateAuthority, bypassManager] channel in
                channel.pipeline.configureHTTPServerPipeline(
                    withPipeliningAssistance: false,
                    withServerUpgrade: upgradeConfig,
                    withErrorHandling: false,
                    withOutboundHeaderValidation: false
                ).flatMap {
                    // Requests that didn't upgrade (i.e. proxied HTTP/HTTPS
                    // traffic) fall through to the normal proxy path.
                    channel.pipeline.addHandler(FrontendHandler(certificateAuthority: certificateAuthority, bypassManager: bypassManager))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)

        return bootstrap.bind(host: host, port: port)
    }
}