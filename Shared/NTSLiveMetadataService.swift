import Foundation

struct NTSNowPlaying: Sendable, Equatable {
    var nts1Title: String?
    var nts2Title: String?

    static let empty = NTSNowPlaying(nts1Title: nil, nts2Title: nil)
}

protocol NTSLiveMetadataFetching: Sendable {
    func fetchNowPlaying() async throws -> NTSNowPlaying
}

struct NTSLiveMetadataService: NTSLiveMetadataFetching {
    private let url: URL
    private let session: URLSession

    init(
        url: URL = AppConstants.ntsLiveAPIURL,
        session: URLSession = .shared
    ) {
        self.url = url
        self.session = session
    }

    func fetchNowPlaying() async throws -> NTSNowPlaying {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(LiveResponse.self, from: data)

        var result = NTSNowPlaying.empty
        for channel in decoded.results {
            let title = channel.now?.broadcast_title
                ?? channel.now?.embeds?.details?.name

            switch channel.channel_name {
            case "1":
                result.nts1Title = title
            case "2":
                result.nts2Title = title
            default:
                continue
            }
        }

        return result
    }
}

// MARK: - DTOs

private struct LiveResponse: Decodable {
    let results: [Channel]
}

private struct Channel: Decodable {
    let channel_name: String
    let now: Show?
}

private struct Show: Decodable {
    let broadcast_title: String?
    let embeds: Embeds?
}

private struct Embeds: Decodable {
    let details: Details?
}

private struct Details: Decodable {
    let name: String?
}
