import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class RadioPlayerService: ObservableObject, PlaybackControlling {
    static let shared = RadioPlayerService()

    @Published private(set) var state: SharedPlayerState

    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "RadioPlayerService")
    private let engine: RadioPlaybackEngine
    private let stateStore: SharedPlayerStateStoring
    private let widgetReloader: WidgetReloading
    private let metadataService: NTSLiveMetadataFetching
    private var externalStateObserver: NSObjectProtocol?
    private var pendingStation: Station?

    init(
        engine: RadioPlaybackEngine = AVPlayerEngine(),
        stateStore: SharedPlayerStateStoring = AppGroupSharedPlayerStateStore(),
        widgetReloader: WidgetReloading = WidgetReloader(),
        metadataService: NTSLiveMetadataFetching = NTSLiveMetadataService(),
        initialState: SharedPlayerState? = nil
    ) {
        self.engine = engine
        self.stateStore = stateStore
        self.widgetReloader = widgetReloader
        self.metadataService = metadataService
        self.state = initialState ?? stateStore.load()

        self.engine.onStateChange = { [weak self] engineState in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.handleEngineState(engineState)
            }
        }
    }

    func play(station: Station) async throws -> SharedPlayerState {
        logger.log("play requested station=\(station.rawValue, privacy: .public)")
        pendingStation = station

        // Write the Connecting state up-front so the widget gets instant
        // feedback even before the engine callback arrives. Subsequent
        // engine `.connecting` callbacks will dedupe against this state.
        applyWithMetadata(
            currentStation: station,
            isPlaying: true,
            statusText: "Connecting \(station.displayName)",
            lastError: nil
        )

        do {
            try engine.load(url: station.streamURL)
            try engine.play()
        } catch {
            return transitionToError(error)
        }

        return state
    }

    func togglePlayback() async throws -> SharedPlayerState {
        let wasPlaying = state.isPlaying
        logger.log("togglePlayback requested wasPlaying=\(wasPlaying, privacy: .public)")

        if state.isPlaying {
            engine.pause()

            applyWithMetadata(
                currentStation: state.currentStation,
                isPlaying: false,
                statusText: "Paused",
                lastError: nil
            )
            return state
        }

        let station = state.currentStation ?? .nts1
        return try await play(station: station)
    }

    func currentState() -> SharedPlayerState {
        state
    }

    func startExternalStateSync() {
        if externalStateObserver == nil {
            externalStateObserver = PlaybackStateSignal.addObserver { [weak self] in
                guard let self else {
                    return
                }

                Task { @MainActor in
                    await self.syncFromSharedState(force: false)
                }
            }
        }

        Task { @MainActor in
            await syncFromSharedState(force: true)
        }
    }

    deinit {
        PlaybackStateSignal.removeObserver(externalStateObserver)
    }

    private func handleEngineState(_ engineState: RadioEngineState) {
        logger.log("engine state=\(String(describing: engineState), privacy: .public)")

        switch engineState {
        case .idle:
            return
        case .connecting:
            let station = pendingStation ?? state.currentStation
            applyWithMetadata(
                currentStation: station,
                isPlaying: true,
                statusText: station.map { "Connecting \($0.displayName)" } ?? "Connecting",
                lastError: nil
            )
        case .playing:
            let station = pendingStation ?? state.currentStation
            applyWithMetadata(
                currentStation: station,
                isPlaying: true,
                statusText: station.map { "Playing \($0.displayName)" } ?? "Playing",
                lastError: nil
            )
            fetchAndPersistMetadata()
        case .paused:
            if !state.isPlaying, (state.lastError ?? "").isEmpty == false {
                return
            }

            applyWithMetadata(
                currentStation: state.currentStation,
                isPlaying: false,
                statusText: "Paused",
                lastError: nil
            )
        case .failed(let message):
            applyWithMetadata(
                currentStation: state.currentStation,
                isPlaying: false,
                statusText: "Unavailable",
                lastError: message
            )
        }
    }

    private func transitionToError(_ error: Error) -> SharedPlayerState {
        logger.error("transitionToError message=\(error.localizedDescription, privacy: .public)")

        applyWithMetadata(
            currentStation: state.currentStation,
            isPlaying: false,
            statusText: "Unavailable",
            lastError: error.localizedDescription
        )
        return state
    }

    /// Apply a new state: dedupe equivalent consecutive states, persist, and
    /// fire exactly one widget reload per meaningful transition. Chronod
    /// budgets widget reloads - firing many in quick succession causes later
    /// provider runs to be delayed. One reload per transition + a single
    /// safety reload is plenty.
    private func apply(_ newState: SharedPlayerState) {
        if isEquivalent(state, newState) {
            logger.log("apply skipped (state unchanged) isPlaying=\(newState.isPlaying, privacy: .public) status=\(newState.statusText, privacy: .public)")
            return
        }

        state = newState
        stateStore.save(newState)
        widgetReloader.reloadTimelines()

        // Schedule one safety reload ~800ms later for this transition. Don't
        // cancel a previously-scheduled safety reload - letting both fire is
        // fine because each safety reload is a single chronod request.
        scheduleSafetyReload(delayMS: 800)
    }

    /// Ignore `updatedAt` so a pure timestamp churn doesn't trigger redundant
    /// keychain writes and widget reloads.
    private func isEquivalent(_ lhs: SharedPlayerState, _ rhs: SharedPlayerState) -> Bool {
        return lhs.currentStation == rhs.currentStation
            && lhs.isPlaying == rhs.isPlaying
            && lhs.statusText == rhs.statusText
            && (lhs.lastError ?? "") == (rhs.lastError ?? "")
            && lhs.nts1NowTitle == rhs.nts1NowTitle
            && lhs.nts2NowTitle == rhs.nts2NowTitle
            && lhs.metadataUpdatedAt == rhs.metadataUpdatedAt
    }

    private func scheduleSafetyReload(delayMS: UInt64) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayMS * 1_000_000)
            guard let self else {
                return
            }

            await MainActor.run {
                self.logger.log("safety reload fired")
                self.widgetReloader.reloadTimelines()
            }
        }
    }

    private func syncFromSharedState(force: Bool) async {
        let desired = stateStore.load()

        if !force, isEquivalent(desired, state) {
            return
        }

        if desired.isPlaying {
            let station = desired.currentStation ?? .nts1
            _ = try? await play(station: station)
            return
        }

        engine.pause()
        var updated = desired
        updated.isPlaying = false
        updated.statusText = "Paused"
        updated.lastError = nil
        updated.updatedAt = .now
        apply(updated)
    }

    private func applyWithMetadata(
        currentStation: Station?,
        isPlaying: Bool,
        statusText: String,
        lastError: String?
    ) {
        let newState = SharedPlayerState(
            currentStation: currentStation,
            isPlaying: isPlaying,
            statusText: statusText,
            lastError: lastError,
            updatedAt: .now,
            nts1NowTitle: state.nts1NowTitle,
            nts2NowTitle: state.nts2NowTitle,
            metadataUpdatedAt: state.metadataUpdatedAt
        )
        apply(newState)
    }

    private func fetchAndPersistMetadata() {
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let nowPlaying = try await metadataService.fetchNowPlaying()
                await MainActor.run {
                    self.mergeMetadata(nowPlaying)
                }
            } catch {
                logger.debug("metadata fetch skipped error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    private func mergeMetadata(_ nowPlaying: NTSNowPlaying) {
        let updated = state.merged(with: nowPlaying)
        guard updated != state else {
            return
        }

        apply(updated)
    }
}
