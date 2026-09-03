import XCTest
@testable import NTSWidgetHost

final class HTMLEntityDecodingTests: XCTestCase {
    /// The exact title the NTS API served while this was being fixed; it was
    /// reaching the widget as "GOD&#039;S WAITING ROOM W/ DAVID HOLMES".
    func testDecodesTheRealWorldApostropheCase() {
        XCTAssertEqual(
            "GOD&#039;S WAITING ROOM W/ DAVID HOLMES".decodingHTMLEntities(),
            "GOD'S WAITING ROOM W/ DAVID HOLMES"
        )
    }

    func testDecodesDecimalHexAndNamedForms() {
        XCTAssertEqual("&#039;".decodingHTMLEntities(), "'")
        XCTAssertEqual("&#39;".decodingHTMLEntities(), "'")
        XCTAssertEqual("&#x27;".decodingHTMLEntities(), "'")
        XCTAssertEqual("&#X27;".decodingHTMLEntities(), "'")
        XCTAssertEqual("&apos;".decodingHTMLEntities(), "'")
        XCTAssertEqual("&quot;a&quot;".decodingHTMLEntities(), "\"a\"")
        XCTAssertEqual("&rsquo;".decodingHTMLEntities(), "’")
        XCTAssertEqual("&hellip;".decodingHTMLEntities(), "…")
        XCTAssertEqual("Jos&eacute;".decodingHTMLEntities(), "José")
    }

    func testNamedEntitiesAreCaseInsensitive() {
        XCTAssertEqual("&AMP;".decodingHTMLEntities(), "&")
        XCTAssertEqual("&Quot;".decodingHTMLEntities(), "\"")
    }

    /// Decoding is single-pass, so a decoded ampersand must not be re-read as
    /// the start of another entity.
    func testDecodedAmpersandIsNotRescanned() {
        XCTAssertEqual("AT&amp;T".decodingHTMLEntities(), "AT&T")
        XCTAssertEqual("&amp;#039;".decodingHTMLEntities(), "&#039;")
    }

    func testLeavesPlainTextAndUnknownOrMalformedEntitiesAlone() {
        XCTAssertEqual("SKYAPNEA w/ Memotone".decodingHTMLEntities(), "SKYAPNEA w/ Memotone")
        XCTAssertEqual("Rock & Roll".decodingHTMLEntities(), "Rock & Roll")
        XCTAssertEqual("&notarealentity;".decodingHTMLEntities(), "&notarealentity;")
        XCTAssertEqual("&".decodingHTMLEntities(), "&")
        XCTAssertEqual("&;".decodingHTMLEntities(), "&;")
        XCTAssertEqual("&#;".decodingHTMLEntities(), "&#;")
        XCTAssertEqual("&#xZZ;".decodingHTMLEntities(), "&#xZZ;")
        // No terminating semicolon within the lookahead window.
        XCTAssertEqual("&#039 missing".decodingHTMLEntities(), "&#039 missing")
        XCTAssertEqual("100% &#037; done".decodingHTMLEntities(), "100% % done")
    }

    func testHandlesMultipleEntitiesAndAdjacentText() {
        XCTAssertEqual(
            "A&#039;B&#039;C".decodingHTMLEntities(),
            "A'B'C"
        )
        XCTAssertEqual(
            "&lt;b&gt;LOUD&lt;/b&gt;".decodingHTMLEntities(),
            "<b>LOUD</b>"
        )
    }

    /// Out-of-range scalars must not crash or produce garbage.
    func testRejectsInvalidScalars() {
        XCTAssertEqual("&#xD800;".decodingHTMLEntities(), "&#xD800;")   // surrogate
        XCTAssertEqual("&#99999999;".decodingHTMLEntities(), "&#99999999;")
    }

    func testDecodesNonBMPScalar() {
        XCTAssertEqual("&#x1F3B5;".decodingHTMLEntities(), "🎵")
    }
}

final class NTSLiveMetadataRequestTests: XCTestCase {
    /// "Now playing" must never be answered from a cache: the API sends
    /// `Cache-Control: max-age=900`, and URLSession.shared was observed
    /// replaying a 40-minute-old show title into the widget.
    func testRequestBypassesTheLocalCache() {
        let request = NTSLiveMetadataService().makeRequest()

        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    func testRequestTargetsTheLiveEndpointWithATimeout() {
        let request = NTSLiveMetadataService().makeRequest()

        XCTAssertEqual(request.url, AppConstants.ntsLiveAPIURL)
        XCTAssertEqual(request.timeoutInterval, 5)
    }
}
