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
        if case .error(let message, let sessionId) = msg {
            XCTAssertEqual(message, "something broke")
            XCTAssertNil(sessionId)
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

    // MARK: - v2 messages

    func testEncodeSessionCreateWithAgent() throws {
        let msg = ClientMessage.sessionCreate(cwd: "/tmp", agent: "codex")
        let data = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["type"] as? String, "session/create")
        XCTAssertEqual(dict["agent"] as? String, "codex")
    }

    func testEncodeSessionCancel() throws {
        let msg = ClientMessage.sessionCancel(sessionId: "abc")
        let data = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["type"] as? String, "session/cancel")
        XCTAssertEqual(dict["sessionId"] as? String, "abc")
    }

    func testEncodePermissionRespond() throws {
        let msg = ClientMessage.permissionRespond(sessionId: "s1", requestId: "r1", optionId: "o1")
        let data = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["type"] as? String, "permission/respond")
        XCTAssertEqual(dict["requestId"] as? String, "r1")
        XCTAssertEqual(dict["optionId"] as? String, "o1")
    }

    func testDecodeEventText() throws {
        let json = #"{"type":"event/text","sessionId":"abc","content":"hello"}"#
        let msg = try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!)
        if case .eventText(let sid, let content) = msg {
            XCTAssertEqual(sid, "abc")
            XCTAssertEqual(content, "hello")
        } else {
            XCTFail("Expected eventText")
        }
    }

    func testDecodeEventToolCall() throws {
        let json = #"{"type":"event/tool_call","sessionId":"s1","toolCallId":"tc1","tool":"read","status":"running"}"#
        let msg = try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!)
        if case .eventToolCall(let sid, let tcId, let tool, let status) = msg {
            XCTAssertEqual(sid, "s1")
            XCTAssertEqual(tcId, "tc1")
            XCTAssertEqual(tool, "read")
            XCTAssertEqual(status, "running")
        } else {
            XCTFail("Expected eventToolCall")
        }
    }

    func testDecodeEventUsage() throws {
        let json = #"{"type":"event/usage","sessionId":"s1","inputTokens":500,"outputTokens":200}"#
        let msg = try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!)
        if case .eventUsage(let sid, let input, let output) = msg {
            XCTAssertEqual(sid, "s1")
            XCTAssertEqual(input, 500)
            XCTAssertEqual(output, 200)
        } else {
            XCTFail("Expected eventUsage")
        }
    }

    func testDecodeEventTurnEnd() throws {
        let json = #"{"type":"event/turn_end","sessionId":"s1","stopReason":"end_turn"}"#
        let msg = try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!)
        if case .eventTurnEnd(let sid, let reason) = msg {
            XCTAssertEqual(sid, "s1")
            XCTAssertEqual(reason, "end_turn")
        } else {
            XCTFail("Expected eventTurnEnd")
        }
    }

    func testDecodeEventSessionInfo() throws {
        let json = #"{"type":"event/session_info","sessionId":"s1","agent":"claude","models":["opus","sonnet"]}"#
        let msg = try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!)
        if case .eventSessionInfo(let sid, let agent, let models, let modes) = msg {
            XCTAssertEqual(sid, "s1")
            XCTAssertEqual(agent, "claude")
            XCTAssertEqual(models, ["opus", "sonnet"])
            XCTAssertNil(modes)
        } else {
            XCTFail("Expected eventSessionInfo")
        }
    }

    func testDecodeSessionDestroyed() throws {
        let json = #"{"type":"session/destroyed","sessionId":"abc"}"#
        let msg = try decoder.decode(DaemonMessage.self, from: json.data(using: .utf8)!)
        if case .sessionDestroyed(let sid) = msg {
            XCTAssertEqual(sid, "abc")
        } else {
            XCTFail("Expected sessionDestroyed")
        }
    }
}
