import Foundation
import NIO
import NIOHTTP1
import Core

final class BackendHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let requestHead: HTTPRequestHead
    private let requestBody: [UInt8]
    private let capturedRequest: CapturedRequest
    private let clientChannel: Channel
    private let startTime: Date

    private var responseHead: HTTPResponseHead?
    private var responseBodyBytes: [UInt8] = []
    /// Guards against finish() and errorCaught() both running for the same
    /// exchange — e.g. an error arriving right after .end was already handled.
    private var finished = false

    init(requestHead: HTTPRequestHead,
         requestBody: [UInt8],
         capturedRequest: CapturedRequest,
         clientChannel: Channel,
         startTime: Date) {
        self.requestHead = requestHead
        self.requestBody = requestBody
        self.capturedRequest = capturedRequest
        self.clientChannel = clientChannel
        self.startTime = startTime
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
        guard !finished else {
            context.close(promise: nil)
            return
        }
        finished = true

        FileHandle.standardError.write("Backend connection error: \(error)\n".data(using: .utf8)!)

        writeErrorResponse(status: .badGateway, message: "Upstream error: \(error)")

        let frame = TrafficFrame(
            id: UUID().uuidString,
            timestamp: startTime,
            request: capturedRequest,
            response: nil,
            durationMs: Date().timeIntervalSince(startTime) * 1000,
            error: "\(error)"
        )
        FrameSink.shared.emit(frame)

        context.close(promise: nil)
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
        guard !finished else { return }
        finished = true
        defer { context.close(promise: nil) }

        guard let head = responseHead else { return }

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

        let frame = TrafficFrame(
            id: UUID().uuidString,
            timestamp: startTime,
            request: capturedRequest,
            response: capturedResponse,
            durationMs: Date().timeIntervalSince(startTime) * 1000
        )

        FrameSink.shared.emit(frame)
    }
}