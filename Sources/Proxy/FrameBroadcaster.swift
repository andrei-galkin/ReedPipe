import NIO
import NIOWebSocket
import NIOConcurrencyHelpers

/// Tracks connected WebSocket clients (browser frontends listening on `/ws`)
/// and broadcasts captured-frame JSON to all of them.
///
/// Registration happens from `WebSocketHandler.handlerAdded`/`handlerRemoved`,
/// which run on that connection's own event loop; `broadcast` is called from
/// `FrameSink.emit`, which can run on any of the proxy's event loops. All of
/// that is why `channels` is behind a lock rather than assumed single-threaded.
final class FrameBroadcaster {
    static let shared = FrameBroadcaster()

    private let lock = NIOLock()
    private var channels: [ObjectIdentifier: Channel] = [:]

    private init() {}

    func register(_ channel: Channel) {
        lock.withLock {
            channels[ObjectIdentifier(channel)] = channel
        }
    }

    func unregister(_ channel: Channel) {
        _ = lock.withLock {
            channels.removeValue(forKey: ObjectIdentifier(channel))
        }
    }

    /// Sends `text` as a single WebSocket text frame to every connected client.
    /// Safe to call with zero clients connected (e.g. before the frontend has
    /// opened its socket) — it's just a no-op in that case.
    func broadcast(text: String) {
        let targets = lock.withLock { Array(channels.values) }
        guard !targets.isEmpty else { return }

        for channel in targets {
            var buffer = channel.allocator.buffer(capacity: text.utf8.count)
            buffer.writeString(text)
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
            channel.writeAndFlush(frame, promise: nil)
        }
    }

    /// Test/diagnostic helper — how many WebSocket clients are currently connected.
    var connectedCount: Int {
        lock.withLock { channels.count }
    }
}