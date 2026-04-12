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

    // MARK: - Whitespace Trimming (#42)

    func testHostWithTrailingNewlineIsValid() {
        let config = ConnectionConfig(host: "127.0.0.1\n", port: 7842, token: "abc123")
        XCTAssertTrue(config.isValid, "Host with trailing newline should still be valid")
        XCTAssertEqual(config.wsURL?.absoluteString, "ws://127.0.0.1:7842")
    }

    func testTokenWithTrailingNewlineIsValid() {
        let config = ConnectionConfig(host: "localhost", port: 7842, token: "abc123\n")
        XCTAssertTrue(config.isValid, "Token with trailing newline should still be valid")
    }

    func testHostWithWhitespaceIsValid() {
        let config = ConnectionConfig(host: "  192.168.1.1  ", port: 7842, token: "abc")
        XCTAssertTrue(config.isValid, "Host with surrounding spaces should still be valid")
        XCTAssertEqual(config.wsURL?.absoluteString, "ws://192.168.1.1:7842")
    }

    func testWhitespaceOnlyHostIsInvalid() {
        let config = ConnectionConfig(host: "  \n  ", port: 7842, token: "abc")
        XCTAssertFalse(config.isValid, "Whitespace-only host should be invalid")
    }

    func testWhitespaceOnlyTokenIsInvalid() {
        let config = ConnectionConfig(host: "localhost", port: 7842, token: "  \n  ")
        XCTAssertFalse(config.isValid, "Whitespace-only token should be invalid")
    }
}
