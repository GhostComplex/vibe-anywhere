import Foundation

struct ConnectionConfig: Sendable, Equatable {
    var host: String
    var port: Int
    var token: String

    var wsURL: URL? {
        URL(string: "ws://\(host.trimmingCharacters(in: .whitespacesAndNewlines)):\(port)")
    }

    var isValid: Bool {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return !h.isEmpty && port > 0 && port <= 65535 && !t.isEmpty && wsURL != nil
    }

    static let empty = ConnectionConfig(host: "", port: 7842, token: "")
}
