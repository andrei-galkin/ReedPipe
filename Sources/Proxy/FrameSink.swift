import Foundation
import NIOConcurrencyHelpers
import Core

/// Single place where captured Frames leave the proxy pipeline: pretty-printed
/// to stdout for local debugging, and broadcast as JSON to any connected
/// WebSocket clients (browser frontends on `/ws`) via FrameBroadcaster.
///
/// `emit` can be called concurrently — each proxied request's BackendHandler
/// finishes on whatever event loop its connection landed on, so with
/// MultiThreadedEventLoopGroup this genuinely runs from multiple threads at
/// once. The lock keeps the stdout output from interleaving; FrameBroadcaster
/// has its own lock guarding the connected-clients set.
final class FrameSink {
    static let shared = FrameSink()

    private let encoder: JSONEncoder = {
        let e = FrameCoding.makeEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let lock = NIOLock()

    private init() {}

    func emit(_ frame: TrafficFrame) {
        do {
            let data = try encoder.encode(frame)
            let json = String(data: data, encoding: .utf8) ?? "<encoding error>"
            lock.withLock {
                print("\n=== Captured frame \(frame.id) ===")
                print(json)
            }
            FrameBroadcaster.shared.broadcast(text: json)
        } catch {
            FileHandle.standardError.write("Failed to encode frame: \(error)\n".data(using: .utf8)!)
        }
    }
}