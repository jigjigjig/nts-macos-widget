import Foundation

enum Station: String, CaseIterable, Codable, Identifiable, Sendable {
    case nts1
    case nts2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nts1:
            return "NTS 1"
        case .nts2:
            return "NTS 2"
        }
    }

    var badgeLabel: String {
        switch self {
        case .nts1:
            return "1"
        case .nts2:
            return "2"
        }
    }

    var streamURL: URL {
        switch self {
        case .nts1:
            return URL(string: "https://stream-relay-geo.ntslive.net/stream")!
        case .nts2:
            return URL(string: "https://stream-relay-geo.ntslive.net/stream2")!
        }
    }
}
