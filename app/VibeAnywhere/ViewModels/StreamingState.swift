import Foundation
import Observation
import os.log

private let cpuLog = Logger(subsystem: "com.ghostcomplex.VibeAnywhere", category: "CPUDebug")

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
        if text.count % 200 < chunk.count {
            cpuLog.info("[StreamingState] appendText total=\(self.text.count)")
        }
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
        cpuLog.info("[StreamingState] begin()")
        text = ""
        toolUses = []
        isActive = true
    }

    /// Finalize and return the accumulated text + tools.
    func finalize() -> (text: String, toolUses: [ToolUseInfo]) {
        cpuLog.info("[StreamingState] finalize() textLen=\(self.text.count) tools=\(self.toolUses.count)")
        let result = (text: text, toolUses: toolUses)
        text = ""
        toolUses = []
        isActive = false
        return result
    }

    func reset() {
        text = ""
        toolUses = []
        isActive = false
    }
}
