import XCTest
@testable import AriaRuntimeShared

final class JSONValueTests: XCTestCase {
    func testRoundTripObject() throws {
        let payload = JSONValue.object([
            "name": .string("aria"),
            "enabled": .bool(true),
            "count": .number(2),
            "items": .array([.string("a"), .string("b")]),
        ])

        let data = try JSONEncoder.runtimeEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertEqual(decoded, payload)
    }

    func testSubscriptAccess() {
        let payload = JSONValue.object([
            "text": .string("hello"),
        ])

        XCTAssertEqual(payload["text"]?.stringValue, "hello")
        XCTAssertNil(payload["missing"])
    }
}
