import Foundation

// MARK: - Client → Daemon

enum ClientMessage: Encodable {
    case sessionCreate(cwd: String, agent: String? = nil)
    case sessionList
    case sessionResume(sessionId: String)
    case sessionMessage(sessionId: String, content: String)
    case sessionDestroy(sessionId: String)
    case sessionCancel(sessionId: String)
    case sessionSetMode(sessionId: String, mode: String)
    case sessionSetModel(sessionId: String, model: String)
    case permissionRespond(sessionId: String, requestId: String, optionId: String)

    private enum CodingKeys: String, CodingKey {
        case type, cwd, agent, sessionId, content, mode, model, requestId, optionId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sessionCreate(let cwd, let agent):
            try container.encode("session/create", forKey: .type)
            try container.encode(cwd, forKey: .cwd)
            try container.encodeIfPresent(agent, forKey: .agent)
        case .sessionList:
            try container.encode("session/list", forKey: .type)
        case .sessionResume(let sessionId):
            try container.encode("session/resume", forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
        case .sessionMessage(let sessionId, let content):
            try container.encode("session/message", forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(content, forKey: .content)
        case .sessionDestroy(let sessionId):
            try container.encode("session/destroy", forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
        case .sessionCancel(let sessionId):
            try container.encode("session/cancel", forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
        case .sessionSetMode(let sessionId, let mode):
            try container.encode("session/set-mode", forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(mode, forKey: .mode)
        case .sessionSetModel(let sessionId, let model):
            try container.encode("session/set-model", forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(model, forKey: .model)
        case .permissionRespond(let sessionId, let requestId, let optionId):
            try container.encode("permission/respond", forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(optionId, forKey: .optionId)
        }
    }
}

// MARK: - Daemon → Client

enum DaemonMessage {
    // v1
    case sessionCreated(sessionId: String, cwd: String)
    case sessionDestroyed(sessionId: String)
    case sessionList(sessions: [SessionInfo])
    case streamText(sessionId: String, content: String)
    case streamToolUse(sessionId: String, tool: String, input: [String: AnyCodable])
    case streamEnd(sessionId: String, result: String)
    case error(message: String, sessionId: String?)
    // v2 events
    case eventText(sessionId: String, content: String)
    case eventToolCall(sessionId: String, toolCallId: String, tool: String, status: String)
    case eventToolCallUpdate(sessionId: String, toolCallId: String, status: String?, content: String?)
    case eventPermissionRequest(sessionId: String, requestId: String, tool: String, options: [PermissionOption])
    case eventUsage(sessionId: String, inputTokens: Int, outputTokens: Int)
    case eventTurnEnd(sessionId: String, stopReason: String)
    case eventError(sessionId: String, message: String)
    case eventSessionInfo(sessionId: String, agent: String, models: [String]?, modes: [String]?)
}

struct PermissionOption: Codable, Sendable, Identifiable {
    let optionId: String
    let name: String
    let kind: String

    var id: String { optionId }
}

extension DaemonMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, sessionId, cwd, sessions, content, tool, input, result, message
        case toolCallId, status, requestId, options, agent, models, modes
        case inputTokens, outputTokens, stopReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "session/created":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let cwd = try container.decode(String.self, forKey: .cwd)
            self = .sessionCreated(sessionId: sessionId, cwd: cwd)
        case "session/destroyed":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            self = .sessionDestroyed(sessionId: sessionId)
        case "session/list":
            let sessions = try container.decode([SessionInfo].self, forKey: .sessions)
            self = .sessionList(sessions: sessions)
        case "stream/text":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let content = try container.decode(String.self, forKey: .content)
            self = .streamText(sessionId: sessionId, content: content)
        case "stream/tool_use":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let tool = try container.decode(String.self, forKey: .tool)
            let input = try container.decodeIfPresent([String: AnyCodable].self, forKey: .input) ?? [:]
            self = .streamToolUse(sessionId: sessionId, tool: tool, input: input)
        case "stream/end":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let result = try container.decode(String.self, forKey: .result)
            self = .streamEnd(sessionId: sessionId, result: result)
        case "error":
            let message = try container.decode(String.self, forKey: .message)
            let sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
            self = .error(message: message, sessionId: sessionId)
        case "event/text":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let content = try container.decode(String.self, forKey: .content)
            self = .eventText(sessionId: sessionId, content: content)
        case "event/tool_call":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let toolCallId = try container.decode(String.self, forKey: .toolCallId)
            let tool = try container.decode(String.self, forKey: .tool)
            let status = try container.decode(String.self, forKey: .status)
            self = .eventToolCall(sessionId: sessionId, toolCallId: toolCallId, tool: tool, status: status)
        case "event/tool_call_update":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let toolCallId = try container.decode(String.self, forKey: .toolCallId)
            let status = try container.decodeIfPresent(String.self, forKey: .status)
            let content = try container.decodeIfPresent(String.self, forKey: .content)
            self = .eventToolCallUpdate(sessionId: sessionId, toolCallId: toolCallId, status: status, content: content)
        case "event/permission_request":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let requestId = try container.decode(String.self, forKey: .requestId)
            let tool = try container.decode(String.self, forKey: .tool)
            let options = try container.decode([PermissionOption].self, forKey: .options)
            self = .eventPermissionRequest(sessionId: sessionId, requestId: requestId, tool: tool, options: options)
        case "event/usage":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let inputTokens = try container.decode(Int.self, forKey: .inputTokens)
            let outputTokens = try container.decode(Int.self, forKey: .outputTokens)
            self = .eventUsage(sessionId: sessionId, inputTokens: inputTokens, outputTokens: outputTokens)
        case "event/turn_end":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let stopReason = try container.decode(String.self, forKey: .stopReason)
            self = .eventTurnEnd(sessionId: sessionId, stopReason: stopReason)
        case "event/error":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let message = try container.decode(String.self, forKey: .message)
            self = .eventError(sessionId: sessionId, message: message)
        case "event/session_info":
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let agent = try container.decode(String.self, forKey: .agent)
            let models = try container.decodeIfPresent([String].self, forKey: .models)
            let modes = try container.decodeIfPresent([String].self, forKey: .modes)
            self = .eventSessionInfo(sessionId: sessionId, agent: agent, models: models, modes: modes)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown message type: \(type)"
            )
        }
    }
}

// MARK: - AnyCodable (lightweight type-erased wrapper)

struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }
}
