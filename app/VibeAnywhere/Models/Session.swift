import Foundation

struct SessionInfo: Codable, Identifiable, Sendable {
    let sessionId: String
    let cwd: String

    var id: String { sessionId }
}
