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

    /// The live-metadata request, built so it cannot be answered from a cache.
    ///
    /// The API responds with `Cache-Control: public, max-age=900`, so
    /// `URLSession.shared` will happily replay a previous body — observed in
    /// practice serving a 40-minute-old show title from
    /// `~/Library/Caches/com.fede.NTSWidgetHost/fsCachedData`, which is how a
    /// finished show kept showing in the widget. "Now playing" must never come
    /// from a cache.
    ///
    /// Note this only defeats the *local* cache; the endpoint also sits behind
    /// CloudFront (`x-cache: Hit from cloudfront`), so the origin's own value
    /// can still lag by up to its max-age. Nothing client-side can fix that.
    func makeRequest() -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    func fetchNowPlaying() async throws -> NTSNowPlaying {
        let request = makeRequest()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(LiveResponse.self, from: data)

        var result = NTSNowPlaying.empty
        for channel in decoded.results {
            // The API returns HTML-escaped titles ("GOD&#039;S WAITING ROOM"),
            // so decode here — at the boundary — and keep escaped text out of
            // the shared state and the widget entirely.
            let title = (channel.now?.broadcast_title
                ?? channel.now?.embeds?.details?.name)?
                .decodingHTMLEntities()

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

// MARK: - HTML entity decoding

extension String {
    /// Decodes the HTML entities the NTS API embeds in show titles, e.g.
    /// `GOD&#039;S WAITING ROOM` -> `GOD'S WAITING ROOM`.
    ///
    /// Deliberately hand-rolled rather than using `NSAttributedString`'s HTML
    /// importer: that pulls in WebKit, must run on the main thread, and is far
    /// too heavy for a metadata fetch feeding a widget. This covers numeric
    /// entities (decimal and hex) plus the named ones that occur in practice.
    ///
    /// Single-pass by design — output is never re-scanned, so a title that
    /// legitimately contains an ampersand (`AT&amp;T` -> `AT&T`) cannot be
    /// mangled by a second decode round.
    func decodingHTMLEntities() -> String {
        guard contains("&") else {
            return self
        }

        // Longest body we support ("#x1F3B5") plus slack.
        let maxEntityLength = 10

        var output = ""
        output.reserveCapacity(count)

        var index = startIndex
        while index < endIndex {
            let character = self[index]
            guard character == "&" else {
                output.append(character)
                index = self.index(after: index)
                continue
            }

            let searchEnd = self.index(index, offsetBy: maxEntityLength + 1, limitedBy: endIndex) ?? endIndex
            let bodyStart = self.index(after: index)

            guard bodyStart < endIndex,
                  let semicolon = self[bodyStart..<searchEnd].firstIndex(of: ";"),
                  let decoded = Self.decodeHTMLEntityBody(String(self[bodyStart..<semicolon])) else {
                output.append(character)
                index = self.index(after: index)
                continue
            }

            output.append(decoded)
            index = self.index(after: semicolon)
        }

        return output
    }

    private static func decodeHTMLEntityBody(_ body: String) -> String? {
        if body.isEmpty {
            return nil
        }

        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let scalarValue: UInt32?

            if digits.first == "x" || digits.first == "X" {
                scalarValue = UInt32(digits.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(digits, radix: 10)
            }

            guard let scalarValue, let scalar = Unicode.Scalar(scalarValue) else {
                return nil
            }

            return String(Character(scalar))
        }

        return namedHTMLEntities[body.lowercased()]
    }

    private static let namedHTMLEntities: [String: String] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "nbsp": "\u{00A0}",
        "ndash": "–",
        "mdash": "—",
        "hellip": "…",
        "lsquo": "‘",
        "rsquo": "’",
        "ldquo": "“",
        "rdquo": "”",
        "eacute": "é",
        "egrave": "è",
        "agrave": "à",
        "ouml": "ö",
        "uuml": "ü",
        "auml": "ä",
        "ccedil": "ç",
        "ntilde": "ñ"
    ]
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
