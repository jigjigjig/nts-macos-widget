import AppIntents
import os

@available(macOS 14.0, *)
struct PlayStationIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Station"
    static var description = IntentDescription("Start playback for a live NTS station.")
    // Route execution to the host app process so AVPlayer lives in a durable
    // process. The widget extension is short-lived and tears down AVPlayer
    // before a live stream can start. The host app is `.accessory`, so no
    // visible window appears when it is launched to handle the intent.
    static var openAppWhenRun = true
    static var isDiscoverable = false

    @Parameter(title: "Station")
    var station: Station

    init() {
        station = .nts1
    }

    init(station: Station) {
        self.station = station
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$station)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "PlayStationIntent")
        let processName = ProcessInfo.processInfo.processName
        logger.log("perform begin station=\(station.rawValue, privacy: .public) process=\(processName, privacy: .public)")

        do {
            let result = try await PlaybackControllerLocator.controller.play(station: station)
            logger.log("perform end station=\(station.rawValue, privacy: .public) isPlaying=\(result.isPlaying, privacy: .public) status=\(result.statusText, privacy: .public)")
        } catch {
            logger.error("perform failed station=\(station.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        }

        return .result()
    }
}
