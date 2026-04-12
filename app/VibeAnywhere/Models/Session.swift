import Foundation

struct SessionInfo: Codable, Identifiable, Sendable {
    let sessionId: String
    let cwd: String
    let agent: String?

    var id: String { sessionId }

    /// Display-friendly agent name
    var agentDisplayName: String {
        agent ?? "claude"
    }
}
