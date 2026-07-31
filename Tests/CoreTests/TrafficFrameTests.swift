import XCTest
@testable import Core

final class TrafficFrameTests: XCTestCase {
    func testFrameCodingRoundTripUsesISO8601Dates() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let request = CapturedRequest(
            method: "GET",
            url: "https://example.com",
            headers: [CapturedHeader(name: "Host", value: "example.com")],
            body: nil,
            bodyIsBase64: false
        )
        let response = CapturedResponse(
            statusCode: 200,
            reason: "OK",
            headers: [CapturedHeader(name: "Content-Type", value: "text/plain")],
            body: "hello",
            bodyIsBase64: false
        )
        let frame = TrafficFrame(
            id: "1",
            timestamp: timestamp,
            request: request,
            response: response,
            durationMs: 12.5
        )

        let encoder = FrameCoding.makeEncoder()
        let data = try encoder.encode(frame)
        let decoder = FrameCoding.makeDecoder()
        let decoded = try decoder.decode(TrafficFrame.self, from: data)

        XCTAssertEqual(decoded, frame)
    }
}
