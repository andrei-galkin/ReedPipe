import Core

/// In-memory, ordered store of captured frames, keyed by id.
///
/// Every frame the proxy broadcasts is already complete (request + response,
/// or request + error) by the time it's sent — see FrameSink on the Proxy
/// side — so in practice every id should be new. `upsert` still handles a
/// repeat id defensively (update in place rather than duplicate), since nothing
/// stops that assumption from changing later (e.g. if a future version starts
/// pushing an in-flight frame before the response arrives).
final class SessionStore {
    private(set) var frames: [TrafficFrame] = []
    private var indexByID: [String: Int] = [:]

    /// Returns true if this was a new frame (appended), false if it updated
    /// an existing one in place — callers use this to decide whether to
    /// append a new DOM row or refresh an existing one.
    @discardableResult
    func upsert(_ frame: TrafficFrame) -> Bool {
        if let index = indexByID[frame.id] {
            frames[index] = frame
            return false
        } else {
            indexByID[frame.id] = frames.count
            frames.append(frame)
            return true
        }
    }
}