import SwiftUI
import os
#if canImport(AppKit)
import AppKit
#endif
#if canImport(MediaPlayer)
import Combine
import MediaPlayer
#endif

@MainActor
@main
struct NTSWidgetHostApp: App {
    private let mediaControls: HostMediaControls?

    init() {
        let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "NTSWidgetHostApp")
        logger.log("host app init pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")

        let service = RadioPlayerService.shared
        PlaybackControllerLocator.controller = service
        #if canImport(MediaPlayer)
        mediaControls = HostMediaControls(service: service)
        #else
        mediaControls = nil
        #endif
        #if canImport(AppKit)
        // LSUIElement hides the app from the Dock/Cmd-Tab; .accessory keeps it
        // eligible to handle WidgetKit App Intents without presenting UI.
        NSApplication.shared.setActivationPolicy(.accessory)
        #endif

        logger.log("host app ready controller=RadioPlayerService")
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

#if canImport(MediaPlayer)
@MainActor
private final class HostMediaControls {
    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "HostMediaControls")
    private weak var service: RadioPlayerService?
    private let commandCenter = MPRemoteCommandCenter.shared()

    private var toggleTarget: Any?
    private var playTarget: Any?
    private var pauseTarget: Any?
    private var nextTrackTarget: Any?
    private var previousTrackTarget: Any?
    private var stateObservation: AnyCancellable?

    init(service: RadioPlayerService) {
        self.service = service
        configureCommands()
        observeServiceState(service)
        updateNowPlayingInfo(with: service.currentState())
    }

    deinit {
        if let toggleTarget {
            commandCenter.togglePlayPauseCommand.removeTarget(toggleTarget)
        }

        if let playTarget {
            commandCenter.playCommand.removeTarget(playTarget)
        }

        if let pauseTarget {
            commandCenter.pauseCommand.removeTarget(pauseTarget)
        }

        if let nextTrackTarget {
            commandCenter.nextTrackCommand.removeTarget(nextTrackTarget)
        }

        if let previousTrackTarget {
            commandCenter.previousTrackCommand.removeTarget(previousTrackTarget)
        }
    }

    private func configureCommands() {
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true

        toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleToggle() ?? .commandFailed
        }
        playTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handlePlay() ?? .commandFailed
        }
        pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handlePause() ?? .commandFailed
        }
        nextTrackTarget = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.handleNextTrack() ?? .commandFailed
        }
        previousTrackTarget = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.handlePreviousTrack() ?? .commandFailed
        }
    }

    private func observeServiceState(_ service: RadioPlayerService) {
        stateObservation = service.$state.sink { [weak self] state in
            self?.updateNowPlayingInfo(with: state)
        }
    }

    private func handleToggle() -> MPRemoteCommandHandlerStatus {
        guard let service else {
            return .noActionableNowPlayingItem
        }

        logger.log("received togglePlayPause command")
        Task { @MainActor in
            _ = try? await service.togglePlayback()
        }
        return .success
    }

    private func handlePlay() -> MPRemoteCommandHandlerStatus {
        guard let service else {
            return .noActionableNowPlayingItem
        }

        if service.currentState().isPlaying {
            return .success
        }

        logger.log("received play command")
        Task { @MainActor in
            _ = try? await service.togglePlayback()
        }
        return .success
    }

    private func handlePause() -> MPRemoteCommandHandlerStatus {
        guard let service else {
            return .noActionableNowPlayingItem
        }

        if !service.currentState().isPlaying {
            return .success
        }

        logger.log("received pause command")
        Task { @MainActor in
            _ = try? await service.togglePlayback()
        }
        return .success
    }

    private func handleNextTrack() -> MPRemoteCommandHandlerStatus {
        guard let service else {
            return .noActionableNowPlayingItem
        }

        logger.log("received nextTrack command")
        let targetStation = cycledStation(from: service.currentState().currentStation, direction: 1)
        Task { @MainActor in
            _ = try? await service.play(station: targetStation)
        }
        return .success
    }

    private func handlePreviousTrack() -> MPRemoteCommandHandlerStatus {
        guard let service else {
            return .noActionableNowPlayingItem
        }

        logger.log("received previousTrack command")
        let targetStation = cycledStation(from: service.currentState().currentStation, direction: -1)
        Task { @MainActor in
            _ = try? await service.play(station: targetStation)
        }
        return .success
    }

    private func cycledStation(from current: Station?, direction: Int) -> Station {
        let stations: [Station] = [.nts1, .nts2]
        let currentIndex = stations.firstIndex(of: current ?? .nts1) ?? 0
        let shiftedIndex = (currentIndex + direction + stations.count) % stations.count
        return stations[shiftedIndex]
    }

    private func updateNowPlayingInfo(with state: SharedPlayerState) {
        let currentTitle = state.currentStation.flatMap(state.nowTitle(for:)) ?? ""

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyArtist: "NTS Radio",
            MPMediaItemPropertyTitle: currentTitle.isEmpty ? "Live Radio" : currentTitle
        ]

        if let station = state.currentStation {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = station.displayName
        } else {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "NTS"
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = state.isPlaying ? .playing : .paused
    }
}
#endif
