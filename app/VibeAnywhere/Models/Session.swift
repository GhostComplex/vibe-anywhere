import Foundation

struct SessionInfo: Codable, Identifiable, Sendable {
    let sessionId: String
    let cwd: String
    let agent: String?
    let title: String?

    var id: String { sessionId }

    /// Display-friendly agent name
    var agentDisplayName: String {
        agent ?? "claude"
    }

    /// Display-friendly title: title > directory name
    var displayTitle: String {
        title ?? cwd.components(separatedBy: "/").last ?? cwd
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

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private nonisolated(unsafe) static let isoFallback = ISO8601DateFormatter()
    private nonisolated(unsafe) static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var relativeDate: String? {
        guard let updatedAt else { return nil }
        guard let date = Self.isoFormatter.date(from: updatedAt)
                ?? Self.isoFallback.date(from: updatedAt) else { return nil }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
