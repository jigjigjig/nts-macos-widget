import AppIntents
import os

@available(macOS 14.0, *)
struct TogglePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Playback"
    static var description = IntentDescription("Toggle live playback for the current NTS station.")
    // See PlayStationIntent for why this is true. The host app owns AVPlayer.
    static var openAppWhenRun = true
    static var isDiscoverable = false

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle playback")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "TogglePlaybackIntent")
        let processName = ProcessInfo.processInfo.processName
        logger.log("perform begin process=\(processName, privacy: .public)")

        do {
            let result = try await PlaybackControllerLocator.controller.togglePlayback()
            logger.log("perform end isPlaying=\(result.isPlaying, privacy: .public) status=\(result.statusText, privacy: .public)")
        } catch {
            logger.error("perform failed error=\(error.localizedDescription, privacy: .public)")
            throw error
        }

        return .result()
    }
}
