import XCTest
@testable import NTSWidgetHost

final class StationTests: XCTestCase {
    func testDisplayNamesMatchExpectedStations() {
        XCTAssertEqual(Station.nts1.displayName, "NTS 1")
        XCTAssertEqual(Station.nts2.displayName, "NTS 2")
    }

    func testStreamURLsUsePublishedLiveEndpoints() {
        XCTAssertEqual(Station.nts1.streamURL.absoluteString, "https://stream-relay-geo.ntslive.net/stream")
        XCTAssertEqual(Station.nts2.streamURL.absoluteString, "https://stream-relay-geo.ntslive.net/stream2")
    }
}
