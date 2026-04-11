import XCTest
@testable import VibeAnywhere

final class MessageCodingTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - ClientMessage encoding

    func testEncodeSessionCreate() throws {
        let msg = ClientMessage.sessionCreate(cwd: "/tmp/project")
        let data = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["type"] as? String, "session/create")
        XCTAssertEqual(dict["cwd"] as? String, "/tmp/project")
    }

    func testEncodeSessionList() throws {
        let msg = ClientMessage.sessionList
        let data = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["type"] as? String, "session/list")
    }

    func testEncodeSessionMessage() throws {
        let msg = ClientMessage.sessionMessage(sessionId: "abc", content: "hello")
        let data = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["type"] as? String, "session/message")
        XCTAssertEqual(dict["sessionId"] as? String, "abc")
        XCTAssertEqual(dict["content"] as? String, "hello")
    }

    func testEncodeSessionDestroy() throws {
        let msg = ClientMessage.sessionDestroy(sessionId: "xyz")
        let data = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["type"] as? String, "session/destroy")
        XCTAssertEqual(dict["sessionId"] as? String, "xyz")
    }

    // MARK: - DaemonMessage decoding

    func testDecodeSessionCreated() throws {
        let json = #"{"type":"session/created","sessionId":"abc-123","cwd":"/tmp"}"#
        let msg = try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!)
        if case .sessionCreated(let sid, let cwd) = msg {
            XCTAssertEqual(sid, "abc-123")
            XCTAssertEqual(cwd, "/tmp")
        } else {
            XCTFail("Expected sessionCreated")
        }
    }

    func testDecodeStreamText() throws {
        let json = #"{"type":"stream/text","sessionId":"abc","content":"hello "}"#
        let msg = try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!)
        if case .streamText(let sid, let content) = msg {
            XCTAssertEqual(sid, "abc")
            XCTAssertEqual(content, "hello ")
        } else {
            XCTFail("Expected streamText")
        }
    }

    func testDecodeStreamEnd() throws {
        let json = #"{"type":"stream/end","sessionId":"abc","result":"done"}"#
        let msg = try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!)
        if case .streamEnd(let sid, let result) = msg {
            XCTAssertEqual(sid, "abc")
            XCTAssertEqual(result, "done")
        } else {
            XCTFail("Expected streamEnd")
        }
    }

    func testDecodeError() throws {
        let json = #"{"type":"error","message":"something broke"}"#
        let msg = try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!)
        if case .error(let message) = msg {
            XCTAssertEqual(message, "something broke")
        } else {
            XCTFail("Expected error")
        }
    }

    func testDecodeSessionList() throws {
        let json = #"{"type":"session/list","sessions":[{"sessionId":"a","cwd":"/tmp"},{"sessionId":"b","cwd":"/home"}]}"#
        let msg = try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!)
        if case .sessionList(let sessions) = msg {
            XCTAssertEqual(sessions.count, 2)
            XCTAssertEqual(sessions[0].sessionId, "a")
            XCTAssertEqual(sessions[1].cwd, "/home")
        } else {
            XCTFail("Expected sessionList")
        }
    }

    func testDecodeUnknownTypeThrows() {
        let json = #"{"type":"unknown/type"}"#
        XCTAssertThrowsError(try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!))
    }
}
