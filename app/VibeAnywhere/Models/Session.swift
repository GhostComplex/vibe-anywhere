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

struct HostSessionInfo: Codable, Identifiable, Sendable {
    let sessionId: String
    let cwd: String
    let title: String?
    let updatedAt: String?

    var id: String { sessionId }

    var displayTitle: String {
        title ?? directoryName
    }

    var directoryName: String {
        cwd.components(separatedBy: "/").last ?? cwd
    }

    var relativeDate: String? {
        guard let updatedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: updatedAt)
                ?? ISO8601DateFormatter().date(from: updatedAt) else { return nil }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
