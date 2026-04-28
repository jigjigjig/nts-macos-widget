import AVFoundation
import Foundation
import os

enum RadioEngineState: Equatable {
    case idle
    case connecting
    case playing
    case paused
    case failed(String)
}

protocol RadioPlaybackEngine: AnyObject {
    var onStateChange: ((RadioEngineState) -> Void)? { get set }
    func load(url: URL) throws
    func play() throws
    func pause()
}

final class AVPlayerEngine: NSObject, RadioPlaybackEngine {
    var onStateChange: ((RadioEngineState) -> Void)?

    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "AVPlayerEngine")
    private let player: AVPlayer
    private var currentItem: AVPlayerItem?
    private var timeControlObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var itemErrorLogObserver: NSObjectProtocol?
    private var failedToPlayToEndObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var intendsToPlay = false
    private var lastPublishedState: RadioEngineState = .idle

    init(player: AVPlayer = AVPlayer()) {
        self.player = player
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        attachPlayerObservers()
    }

    deinit {
        timeControlObservation?.invalidate()
        rateObservation?.invalidate()
        itemStatusObservation?.invalidate()

        if let failedToPlayToEndObserver {
            NotificationCenter.default.removeObserver(failedToPlayToEndObserver)
        }

        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
        }

        if let itemErrorLogObserver {
            NotificationCenter.default.removeObserver(itemErrorLogObserver)
        }
    }

    func load(url: URL) throws {
        logger.log("load url=\(url.absoluteString, privacy: .public)")

        // Pause the old item before swapping so `timeControlStatus` resets to
        // `.paused` and a freshly-replaced item can't leak a transient
        // `.playing` status that triggers a false "Playing" publish before the
        // new stream is actually buffered.
        player.pause()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        currentItem = item
        attachItemObservers(for: item)
        player.replaceCurrentItem(with: item)
        // Any transient playback state from the old item is now irrelevant.
        // Force connecting and wait for the new item to signal readiness.
        publish(.connecting)
    }

    func play() throws {
        logger.log("play intendsToPlay=true")
        intendsToPlay = true
        player.play()
        // Do NOT evaluateState() here - `timeControlStatus` is not reliable
        // the same runloop tick we called play(). Let KVO fire for the real
        // transition.
    }

    func pause() {
        logger.log("pause intendsToPlay=false")
        intendsToPlay = false
        player.pause()
        publish(.paused)
    }

    private func attachPlayerObservers() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            self?.evaluateState()
        }

        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, _ in
            self?.evaluateState()
        }
    }

    private func attachItemObservers(for item: AVPlayerItem) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            guard let self else {
                return
            }

            switch observedItem.status {
            case .readyToPlay:
                self.logger.log("item ready to play")
                self.evaluateState()
            case .failed:
                let message = observedItem.error?.localizedDescription ?? "Stream failed to load."
                self.logger.error("item failed message=\(message, privacy: .public)")
                self.publish(.failed(message))
            case .unknown:
                self.evaluateState()
            @unknown default:
                self.evaluateState()
            }
        }

        if let failedToPlayToEndObserver {
            NotificationCenter.default.removeObserver(failedToPlayToEndObserver)
        }

        failedToPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            guard let self else {
                return
            }

            let itemError = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription
            let fallbackError = item.error?.localizedDescription
            let message = itemError ?? fallbackError ?? "Stream unavailable."
            self.logger.error("item failed to play to end message=\(message, privacy: .public)")
            self.publish(.failed(message))
        }

        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
        }

        stalledObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.logger.log("item stalled")
            self?.publish(.connecting)
        }

        if let itemErrorLogObserver {
            NotificationCenter.default.removeObserver(itemErrorLogObserver)
        }

        itemErrorLogObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newErrorLogEntryNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            if let entries = item.errorLog()?.events, let last = entries.last {
                self.logger.error("item error log code=\(last.errorStatusCode, privacy: .public) domain=\(last.errorDomain, privacy: .public) comment=\(last.errorComment ?? "", privacy: .public)")
            }
        }
    }

    private func evaluateState() {
        if case .failed = lastPublishedState {
            return
        }

        if !intendsToPlay {
            publish(.paused)
            return
        }

        // If the current item hasn't signalled readyToPlay yet, we must be
        // connecting regardless of what the player's `timeControlStatus`
        // reports. `timeControlStatus` can momentarily be `.playing` for a
        // freshly-replaced item before it has actually started to buffer.
        if let status = currentItem?.status, status != .readyToPlay {
            publish(.connecting)
            return
        }

        switch player.timeControlStatus {
        case .playing:
            publish(.playing)
        case .waitingToPlayAtSpecifiedRate:
            publish(.connecting)
        case .paused:
            publish(.connecting)
        @unknown default:
            publish(.connecting)
        }
    }

    private func publish(_ state: RadioEngineState) {
        guard state != lastPublishedState else {
            return
        }

        lastPublishedState = state
        logger.log("state=\(String(describing: state), privacy: .public)")
        onStateChange?(state)
    }
}
