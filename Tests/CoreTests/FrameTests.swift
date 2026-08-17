import XCTest
import Foundation
@testable import Core

final class FrameTests: XCTestCase {

    func testTrafficFrameRoundTripsThroughJSON() throws {
        let request = CapturedRequest(
            method: "GET",
            url: "http://example.com/path?x=1",
            headers: [CapturedHeader(name: "Accept", value: "*/*")],
            body: nil,
            bodyIsBase64: false
        )
        let response = CapturedResponse(
            statusCode: 200,
            reason: "OK",
            headers: [CapturedHeader(name: "Content-Type", value: "text/plain")],
            body: "hello world",
            bodyIsBase64: false
        )
        let frame = TrafficFrame(
            id: "test-id",
            timestamp: "2023-11-14T22:13:20Z",
            request: request,
            response: response,
            durationMs: 12.5
        )

        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(TrafficFrame.self, from: data)

        XCTAssertEqual(decoded, frame)
    }

    func testTrafficFrameWithNoResponseYetIsStillEncodable() throws {
        // Models the moment a request has been captured but the origin
        // server hasn't responded yet.
        let request = CapturedRequest(method: "POST", url: "http://example.com/", headers: [], body: nil, bodyIsBase64: false)
        let frame = TrafficFrame(id: "in-flight", timestamp: "2023-11-14T22:13:20Z", request: request, response: nil, durationMs: nil)

        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(TrafficFrame.self, from: data)

        XCTAssertNil(decoded.response)
        XCTAssertNil(decoded.durationMs)
    }

    func testBodyEncoderPrefersUTF8() {
        let bytes = Array("hello".utf8)
        let (text, isBase64) = BodyEncoder.encode(bytes)

        XCTAssertEqual(text, "hello")
        XCTAssertFalse(isBase64)
    }

    func testBodyEncoderFallsBackToBase64ForBinaryData() {
        // 0xFF 0xFE is not valid UTF-8.
        let bytes: [UInt8] = [0xFF, 0xFE, 0x00, 0x01]
        let (text, isBase64) = BodyEncoder.encode(bytes)

        XCTAssertTrue(isBase64)
        XCTAssertEqual(text, Data(bytes).base64EncodedString())
    }

    func testBodyEncoderReturnsNilForEmptyBody() {
        let (text, isBase64) = BodyEncoder.encode([])

        XCTAssertNil(text)
        XCTAssertFalse(isBase64)
    }
}
