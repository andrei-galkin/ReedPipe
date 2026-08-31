import Foundation
import NIOConcurrencyHelpers
import Core

final class CaptureTransaction {
    let request: CapturedRequest
    let startTime: Date

    private let lock: NIOLock = .init()
    private var emitted: Bool = false

    init(request: CapturedRequest, startTime: Date) {
        self.request = request
        self.startTime = startTime
    }

    @discardableResult
    func emit(response: CapturedResponse) -> Bool {
        self.emit(response: response, error: nil)
    }

    @discardableResult
    func emit(error: Error) -> Bool {
        self.emit(response: nil, error: String(describing: error))
    }

    private func emit(response: CapturedResponse?, error: String?) -> Bool {
        let shouldEmit: Bool = self.lock.withLock {
            guard !self.emitted else { return false }
            self.emitted = true
            return true
        }
        guard shouldEmit else { return false }

        let frame: TrafficFrame = .init(
            id: UUID().uuidString,
            timestamp: FrameCoding.timestamp(self.startTime),
            request: self.request,
            response: response,
            durationMs: Date().timeIntervalSince(self.startTime) * 1000,
            error: error
        )
        FrameSink.shared.emit(frame)
        return true
    }
}
