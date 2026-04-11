import Foundation

struct ConnectionConfig: Sendable, Equatable {
    var host: String
    var port: Int
    var token: String

    var wsURL: URL? {
        URL(string: "ws://\(host):\(port)")
    }

    var isValid: Bool {
        !host.isEmpty && port > 0 && port <= 65535 && !token.isEmpty && wsURL != nil
    }

    static let empty = ConnectionConfig(host: "", port: 7842, token: "")
}
