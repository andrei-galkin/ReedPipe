import XCTest
@testable import Core

final class TrafficFrameTests: XCTestCase {
    func testFrameCodingRoundTripUsesISO8601Dates() throws {
        let timestamp = "2023-11-14T22:13:20Z"
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

        let encoder = JSONEncoder()
        let data = try encoder.encode(frame)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TrafficFrame.self, from: data)

        XCTAssertEqual(decoded, frame)
    }
}
