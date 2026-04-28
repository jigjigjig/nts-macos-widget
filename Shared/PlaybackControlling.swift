import Foundation

@MainActor
protocol PlaybackControlling: AnyObject {
    func play(station: Station) async throws -> SharedPlayerState
    func togglePlayback() async throws -> SharedPlayerState
    func currentState() -> SharedPlayerState
}
