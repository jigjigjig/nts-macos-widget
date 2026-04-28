import AVFoundation
import Foundation
import os

@MainActor
final class WidgetPlaybackController: PlaybackControlling {
    static let shared = WidgetPlaybackController()

    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "WidgetPlaybackController")
    private let player: AVPlayer
    private let stateStore: SharedPlayerStateStoring
    private let widgetReloader: WidgetReloading
    private let metadataService: NTSLiveMetadataFetching

    private var state: SharedPlayerState
    private var failureObserver: NSObjectProtocol?

    init(
        player: AVPlayer = AVPlayer(),
        stateStore: SharedPlayerStateStoring = AppGroupSharedPlayerStateStore(),
        widgetReloader: WidgetReloading = WidgetReloader(),
        metadataService: NTSLiveMetadataFetching = NTSLiveMetadataService()
    ) {
        self.player = player
        self.stateStore = stateStore
        self.widgetReloader = widgetReloader
        self.metadataService = metadataService
        state = stateStore.load()
        observePlayerFailures()
    }

    deinit {
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
    }

    func play(station: Station) async throws -> SharedPlayerState {
        state = stateStore.load()

        player.replaceCurrentItem(with: AVPlayerItem(url: station.streamURL))
        player.play()

        state = makeState(
            currentStation: station,
            isPlaying: true,
            statusText: "Playing \(station.displayName)",
            lastError: nil
        )
        persistAndReload()
        fetchAndPersistMetadata()
        return state
    }

    func togglePlayback() async throws -> SharedPlayerState {
        state = stateStore.load()

        if state.isPlaying {
            player.pause()
            state = makeState(
                currentStation: state.currentStation,
                isPlaying: false,
                statusText: "Paused",
                lastError: nil
            )
            persistAndReload()
            return state
        }

        let station = state.currentStation ?? .nts1
        return try await play(station: station)
    }

    func currentState() -> SharedPlayerState {
        stateStore.load()
    }

    private func observePlayerFailures() {
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else {
                return
            }

            Task { @MainActor in
                let itemError = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                    .localizedDescription
                let fallbackError = self.player.currentItem?.error?.localizedDescription
                let message = itemError ?? fallbackError ?? "Stream unavailable."
                self.transitionToUnavailable(message)
            }
        }
    }

    private func transitionToUnavailable(_ message: String) {
        state = makeState(
            currentStation: state.currentStation,
            isPlaying: false,
            statusText: "Unavailable",
            lastError: message
        )
        persistAndReload()
    }

    private func persistAndReload() {
        stateStore.save(state)
        widgetReloader.reloadTimelines()
    }

    private func makeState(
        currentStation: Station?,
        isPlaying: Bool,
        statusText: String,
        lastError: String?
    ) -> SharedPlayerState {
        SharedPlayerState(
            currentStation: currentStation,
            isPlaying: isPlaying,
            statusText: statusText,
            lastError: lastError,
            updatedAt: .now,
            nts1NowTitle: state.nts1NowTitle,
            nts2NowTitle: state.nts2NowTitle,
            metadataUpdatedAt: state.metadataUpdatedAt
        )
    }

    private func fetchAndPersistMetadata() {
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let nowPlaying = try await self.metadataService.fetchNowPlaying()
                await self.mergeMetadata(nowPlaying)
            } catch {
                logger.debug("metadata fetch skipped error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func mergeMetadata(_ nowPlaying: NTSNowPlaying) {
        let updated = state.merged(with: nowPlaying)
        guard updated != state else {
            return
        }

        state = updated
        persistAndReload()
    }
}

enum PlaybackControllerLocator {
    @MainActor
    static var controller: PlaybackControlling = WidgetPlaybackController.shared
}
