import Foundation
import NIO
import NIOHTTP1
import Core

final class BackendHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let requestHead: HTTPRequestHead
    private let requestBody: [UInt8]
    private let transaction: CaptureTransaction
    private let clientChannel: Channel

    private var responseHead: HTTPResponseHead?
    private var responseBodyBytes: [UInt8] = []
    /// Guards against finish() and errorCaught() both running for the same
    /// exchange — e.g. an error arriving right after .end was already handled.
    private var finished = false

    init(requestHead: HTTPRequestHead,
         requestBody: [UInt8],
         transaction: CaptureTransaction,
         clientChannel: Channel) {
        self.requestHead = requestHead
        self.requestBody = requestBody
        self.transaction = transaction
        self.clientChannel = clientChannel
    }

    func channelActive(context: ChannelHandlerContext) {
        context.write(wrapOutboundOut(.head(requestHead)), promise: nil)
        if !requestBody.isEmpty {
            var buffer = context.channel.allocator.buffer(capacity: requestBody.count)
            buffer.writeBytes(requestBody)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            responseHead = head

        case .body(let buffer):
            responseBodyBytes.append(contentsOf: buffer.readableBytesView)

        case .end:
            finish(context: context)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.fail(context: context, error: error)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard let idleEvent: IdleStateHandler.IdleStateEvent = event as? IdleStateHandler.IdleStateEvent else {
            context.fireUserInboundEventTriggered(event)
            return
        }

        switch idleEvent {
        case .read:
            self.fail(context: context, error: UpstreamFailure.responseTimedOut)
        case .write, .all:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !self.finished {
            self.fail(context: context, error: UpstreamFailure.closedBeforeResponseCompleted)
        }
        context.fireChannelInactive()
    }

    /// Writes a synthetic error response to the original client so it doesn't
    /// hang waiting for a response that will never come.
    private func writeErrorResponse(status: HTTPResponseStatus, message: String) {
        var buffer = clientChannel.allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)

        var head = HTTPResponseHead(version: .http1_1, status: status)
        head.headers.replaceOrAdd(name: "Content-Length", value: "\(buffer.readableBytes)")
        head.headers.replaceOrAdd(name: "Connection", value: "close")

        clientChannel.writeAndFlush(HTTPServerResponsePart.head(head), promise: nil)
        clientChannel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
        clientChannel.writeAndFlush(HTTPServerResponsePart.end(nil)).whenComplete { _ in
            self.clientChannel.close(promise: nil)
        }
    }

    private func finish(context: ChannelHandlerContext) {
        guard !self.finished else { return }

        guard let head: HTTPResponseHead = self.responseHead else {
            self.fail(context: context, error: UpstreamFailure.missingResponseHead)
            return
        }
        self.finished = true
        defer { context.close(promise: nil) }

        var clientHead = HTTPResponseHead(version: .http1_1, status: head.status)
        clientHead.headers = head.headers
        clientHead.headers.replaceOrAdd(name: "Connection", value: "close")

        clientChannel.write(HTTPServerResponsePart.head(clientHead), promise: nil)
        if !responseBodyBytes.isEmpty {
            var buffer = clientChannel.allocator.buffer(capacity: responseBodyBytes.count)
            buffer.writeBytes(responseBodyBytes)
            clientChannel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
        }
        clientChannel.writeAndFlush(HTTPServerResponsePart.end(nil)).whenComplete { _ in
            self.clientChannel.close(promise: nil)
        }

        let capturedHeaders = head.headers.map { CapturedHeader(name: $0.name, value: $0.value) }
        let (bodyText, isBase64) = BodyEncoder.encode(responseBodyBytes)
        let capturedResponse = CapturedResponse(
            statusCode: Int(head.status.code),
            reason: head.status.reasonPhrase,
            headers: capturedHeaders,
            body: bodyText,
            bodyIsBase64: isBase64
        )

        self.transaction.emit(response: capturedResponse)
    }

    private func fail(context: ChannelHandlerContext, error: Error) {
        guard !self.finished else {
            context.close(promise: nil)
            return
        }
        self.finished = true

        guard self.transaction.emit(error: error) else {
            context.close(promise: nil)
            return
        }

        let message: String = "Upstream error: \(error)"
        FileHandle.standardError.write("Backend connection error: \(error)\n".data(using: .utf8)!)

        if self.clientChannel.isActive {
            self.writeErrorResponse(status: .badGateway, message: message)
        }
        context.close(promise: nil)
    }
}
