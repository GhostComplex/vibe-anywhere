import Foundation
import Observation

/// Isolated observable for streaming state.
/// StreamingBubble observes ONLY this object, so chunk updates
/// never trigger ForEach diff on the messages array.
@Observable
@MainActor
final class StreamingState {
    private(set) var text: String = ""
    private(set) var toolUses: [ToolUseInfo] = []
    private(set) var isActive: Bool = false

    func appendText(_ chunk: String) {
        text += chunk
    }

    func appendToolCall(id: String, tool: String, status: String) {
        toolUses.append(ToolUseInfo(id: id, tool: tool, status: status))
    }

    func updateToolCall(id: String, status: String?) {
        if let idx = toolUses.firstIndex(where: { $0.id == id }),
           let status {
            toolUses[idx].status = status
        }
    }

    func begin() {
        text = ""
        toolUses = []
        isActive = true
    }

    /// Finalize and return the accumulated text + tools.
    func finalize() -> (text: String, toolUses: [ToolUseInfo]) {
        let result = (text: text, toolUses: toolUses)
        text = ""
        toolUses = []
        isActive = false
        return result
    }
}
