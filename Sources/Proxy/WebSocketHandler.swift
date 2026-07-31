import NIO
import NIOWebSocket

final class WebSocketHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    func handlerAdded(context: ChannelHandlerContext) {
        FrameBroadcaster.shared.register(context.channel)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        FrameBroadcaster.shared.unregister(context.channel)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .connectionClose:
            var closeData = frame.unmaskedData
            let closePayload = closeData.readSlice(length: closeData.readableBytes) ?? context.channel.allocator.buffer(capacity: 0)
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: closePayload)
            context.writeAndFlush(wrapOutboundOut(closeFrame)).whenComplete { _ in
                context.close(promise: nil)
            }

        case .ping:
            var frameData = frame.data
            if let maskKey = frame.maskKey {
                frameData.webSocketUnmask(maskKey)
            }
            let pongFrame = WebSocketFrame(fin: true, opcode: .pong, data: frameData)
            context.writeAndFlush(wrapOutboundOut(pongFrame), promise: nil)

        case .text, .binary, .pong, .continuation:
            // No inbound protocol from the frontend yet — this is push-only
            // (proxy → browser) for the Week 3 checkpoint.
            break

        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}