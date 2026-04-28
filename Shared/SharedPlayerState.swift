import Foundation

struct SharedPlayerState: Codable, Equatable, Sendable {
    var currentStation: Station?
    var isPlaying: Bool
    var statusText: String
    var lastError: String?
    var updatedAt: Date
    var nts1NowTitle: String? = nil
    var nts2NowTitle: String? = nil
    var metadataUpdatedAt: Date? = nil

    static func idle(updatedAt: Date = .now) -> SharedPlayerState {
        SharedPlayerState(
            currentStation: nil,
            isPlaying: false,
            statusText: "Paused",
            lastError: nil,
            updatedAt: updatedAt,
            nts1NowTitle: nil,
            nts2NowTitle: nil,
            metadataUpdatedAt: nil
        )
    }

    func merged(with nowPlaying: NTSNowPlaying, refreshedAt: Date = .now) -> SharedPlayerState {
        var updated = self
        let nts1 = nowPlaying.nts1Title?.trimmedNonEmpty
        let nts2 = nowPlaying.nts2Title?.trimmedNonEmpty
        let titlesChanged = updated.nts1NowTitle != nts1 || updated.nts2NowTitle != nts2

        updated.nts1NowTitle = nts1
        updated.nts2NowTitle = nts2

        // Keep a useful timestamp without forcing a reload on every poll when
        // titles are unchanged.
        if titlesChanged || updated.metadataUpdatedAt == nil {
            updated.metadataUpdatedAt = refreshedAt
        }

        return updated
    }

    func nowTitle(for station: Station) -> String? {
        switch station {
        case .nts1:
            return nts1NowTitle
        case .nts2:
            return nts2NowTitle
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
