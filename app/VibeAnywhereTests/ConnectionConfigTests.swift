import XCTest
@testable import VibeAnywhere

final class ConnectionConfigTests: XCTestCase {
    func testEmptyConfigIsInvalid() {
        let config = ConnectionConfig.empty
        XCTAssertFalse(config.isValid)
    }

    func testValidConfig() {
        let config = ConnectionConfig(host: "192.168.1.1", port: 7842, token: "abc123")
        XCTAssertTrue(config.isValid)
        XCTAssertNotNil(config.wsURL)
        XCTAssertEqual(config.wsURL?.absoluteString, "ws://192.168.1.1:7842")
    }

    func testInvalidPort() {
        let config = ConnectionConfig(host: "localhost", port: 0, token: "abc")
        XCTAssertFalse(config.isValid)
    }

    func testPortTooHigh() {
        let config = ConnectionConfig(host: "localhost", port: 70000, token: "abc")
        XCTAssertFalse(config.isValid)
    }

    func testEmptyHost() {
        let config = ConnectionConfig(host: "", port: 7842, token: "abc")
        XCTAssertFalse(config.isValid)
    }

    func testEmptyToken() {
        let config = ConnectionConfig(host: "localhost", port: 7842, token: "")
        XCTAssertFalse(config.isValid)
    }

    func testEquality() {
        let a = ConnectionConfig(host: "localhost", port: 7842, token: "abc")
        let b = ConnectionConfig(host: "localhost", port: 7842, token: "abc")
        XCTAssertEqual(a, b)
    }
}
