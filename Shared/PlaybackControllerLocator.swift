import Foundation
import os

@MainActor
final class HostRequiredPlaybackController: PlaybackControlling {
    static let shared = HostRequiredPlaybackController()

    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "HostRequiredPlaybackController")
    private let stateStore: SharedPlayerStateStoring

    private var state: SharedPlayerState

    init(
        stateStore: SharedPlayerStateStoring = AppGroupSharedPlayerStateStore()
    ) {
        self.stateStore = stateStore
        state = stateStore.load()
    }

    func play(station: Station) async throws -> SharedPlayerState {
        state = stateStore.load()
        logger.error("play ignored outside host app process station=\(station.rawValue, privacy: .public)")
        return state
    }

    func togglePlayback() async throws -> SharedPlayerState {
        state = stateStore.load()
        logger.error("toggle ignored outside host app process")
        return state
    }

    func currentState() -> SharedPlayerState {
        stateStore.load()
    }
}

enum PlaybackControllerLocator {
    @MainActor
    static var controller: PlaybackControlling = HostRequiredPlaybackController.shared
}
