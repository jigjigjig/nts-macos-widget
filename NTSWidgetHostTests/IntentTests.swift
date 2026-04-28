import XCTest
@testable import NTSWidgetHost

final class IntentTests: XCTestCase {
    func testIntentsRemainHostRoutedForDurablePlayback() {
        XCTAssertTrue(PlayStationIntent.openAppWhenRun)
        XCTAssertTrue(TogglePlaybackIntent.openAppWhenRun)
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
