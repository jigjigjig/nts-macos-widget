import Foundation
@testable import NTSWidgetHost

enum DummyPlaybackError: Error, LocalizedError {
    case streamUnavailable

    var errorDescription: String? {
        switch self {
        case .streamUnavailable:
            return "Stream unavailable"
        }
    }
}

final class MockRadioPlaybackEngine: RadioPlaybackEngine {
    private(set) var loadedURLs: [URL] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    var loadError: Error?
    var playError: Error?
    var onStateChange: ((RadioEngineState) -> Void)?

    func load(url: URL) throws {
        if let loadError {
            throw loadError
        }
        loadedURLs.append(url)
    }

    func play() throws {
        if let playError {
            throw playError
        }
        playCallCount += 1
    }

    func pause() {
        pauseCallCount += 1
    }

    func simulateEngineState(_ state: RadioEngineState) {
        onStateChange?(state)
    }
}

final class InMemorySharedPlayerStateStore: SharedPlayerStateStoring {
    private(set) var savedStates: [SharedPlayerState] = []
    private var currentState: SharedPlayerState

    init(initialState: SharedPlayerState = .idle()) {
        currentState = initialState
    }

    func load() -> SharedPlayerState {
        currentState
    }

    func save(_ state: SharedPlayerState) {
        currentState = state
        savedStates.append(state)
    }
}

final class MockWidgetReloader: WidgetReloading {
    private(set) var reloadCallCount = 0

    func reloadTimelines() {
        reloadCallCount += 1
    }
}

@MainActor
final class MockPlaybackController: PlaybackControlling {
    private(set) var playedStations: [Station] = []
    private(set) var toggleCallCount = 0
    private(set) var state: SharedPlayerState

    init(initialState: SharedPlayerState = .idle()) {
        state = initialState
    }

    func play(station: Station) async throws -> SharedPlayerState {
        playedStations.append(station)
        state = SharedPlayerState(
            currentStation: station,
            isPlaying: true,
            statusText: "Playing \(station.displayName)",
            lastError: nil,
            updatedAt: .now
        )
        return state
    }

    func togglePlayback() async throws -> SharedPlayerState {
        toggleCallCount += 1
        state = SharedPlayerState(
            currentStation: state.currentStation,
            isPlaying: !state.isPlaying,
            statusText: state.isPlaying ? "Paused" : "Playing \(state.currentStation?.displayName ?? "NTS 1")",
            lastError: nil,
            updatedAt: .now
        )
        return state
    }

    func currentState() -> SharedPlayerState {
        state
    }
}
