import XCTest
@testable import NTSWidgetHost

final class IntentTests: XCTestCase {
    func testIntentsRemainHostRoutedForDurablePlayback() {
        XCTAssertTrue(PlayStationIntent.openAppWhenRun)
        XCTAssertTrue(TogglePlaybackIntent.openAppWhenRun)
    }

    @MainActor
    func testHostRequiredControllerDoesNotMutateStateOutsideHost() async throws {
        let initialState = SharedPlayerState(
            currentStation: .nts1,
            isPlaying: false,
            statusText: "Paused",
            lastError: nil,
            updatedAt: .now
        )
        let store = InMemorySharedPlayerStateStore(initialState: initialState)
        let sut = HostRequiredPlaybackController(stateStore: store)

        _ = try await sut.play(station: .nts2)
        _ = try await sut.togglePlayback()

        XCTAssertEqual(store.savedStates.count, 0)
        XCTAssertFalse(sut.currentState().isPlaying)
        XCTAssertEqual(sut.currentState().currentStation, .nts1)
    }

    @MainActor
    func testPlayStationIntentSelectsRequestedStation() async throws {
        let mock = MockPlaybackController()
        PlaybackControllerLocator.controller = mock

        let intent = PlayStationIntent(station: .nts2)
        _ = try await intent.perform()

        XCTAssertEqual(mock.playedStations, [.nts2])
        XCTAssertEqual(mock.currentState().currentStation, .nts2)
    }

    @MainActor
    func testTogglePlaybackIntentKeepsCurrentStation() async throws {
        let initialState = SharedPlayerState(
            currentStation: .nts1,
            isPlaying: true,
            statusText: "Playing NTS 1",
            lastError: nil,
            updatedAt: .now
        )
        let mock = MockPlaybackController(initialState: initialState)
        PlaybackControllerLocator.controller = mock

        let intent = TogglePlaybackIntent()
        _ = try await intent.perform()

        XCTAssertEqual(mock.toggleCallCount, 1)
        XCTAssertEqual(mock.currentState().currentStation, .nts1)
    }
}

/// The widget's controls are `ntsradio://` links, not App Intents — see
/// `WidgetAction` for why. These guard the encoding both sides depend on.
final class WidgetActionTests: XCTestCase {
    func testPlayActionRoundTripsPerStation() {
        for station in Station.allCases {
            let action = WidgetAction.play(station)

            XCTAssertEqual(WidgetAction(url: action.url), action, station.rawValue)
        }
    }

    func testToggleActionRoundTrips() {
        XCTAssertEqual(WidgetAction(url: WidgetAction.toggle.url), .toggle)
    }

    /// The scheme is declared in NTSWidgetHost/Info.plist; if these drift, taps
    /// stop reaching the app and the widget silently does nothing.
    func testURLsUseTheDeclaredScheme() {
        XCTAssertEqual(WidgetAction.toggle.url.scheme, "ntsradio")
        XCTAssertEqual(WidgetAction.play(.nts2).url.scheme, "ntsradio")
        XCTAssertEqual(AppConstants.urlScheme, "ntsradio")
    }

    func testPlayURLNamesTheStation() {
        XCTAssertEqual(WidgetAction.play(.nts2).url.absoluteString, "ntsradio://play?station=nts2")
        XCTAssertEqual(WidgetAction.toggle.url.absoluteString, "ntsradio://toggle")
    }

    func testUnrelatedOrMalformedURLsAreRejected() {
        let rejected = [
            "https://play?station=nts1",      // wrong scheme
            "ntsradio://unknown",             // unknown action
            "ntsradio://play",                // missing station
            "ntsradio://play?station=nts9"    // unknown station
        ]

        for raw in rejected {
            let url = URL(string: raw)!
            XCTAssertNil(WidgetAction(url: url), raw)
        }
    }
}
