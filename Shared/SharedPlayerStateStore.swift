import Foundation
import os

protocol SharedPlayerStateStoring {
    func load() -> SharedPlayerState
    func save(_ state: SharedPlayerState)
}

/// Shared state store for the widget extension and host app.
///
/// ## Why a plain file in the real home directory?
///
/// Every sandbox-scoped sharing mechanism on macOS needs an entitlement that
/// only a provisioning profile can authorize:
///
/// - `com.apple.security.application-groups` — restricted
/// - `keychain-access-groups` (team-prefixed) — restricted
/// - `com.apple.application-identifier` — required to touch the
///   data-protection keychain at all
///
/// This project is signed by a *free* Apple team, whose provisioning profiles
/// are valid for **7 days**. A distributed build that depends on any of those
/// entitlements stops launching a week after it is built: AMFI refuses to
/// spawn a process whose restricted entitlements are no longer authorized, so
/// the host never starts and the widget renders as an empty black rectangle.
/// That is exactly what happened to the 1.0.1 release (built 2026-07-28,
/// profile expired 2026-08-04).
///
/// To make the app durably launchable we ship with **no restricted
/// entitlements and no embedded provisioning profile**.
///
/// ## Why the file lives inside the *extension's* container
///
/// The two processes are deliberately asymmetric:
///
/// - The **widget extension must be sandboxed**. macOS refuses to register an
///   unsandboxed app extension at all — `pluginkit` reports no match, the
///   widget never loads, and the desktop shows an empty rectangle. Plain
///   `com.apple.security.app-sandbox` needs no provisioning profile, so it is
///   safe to keep.
/// - The **host app is unsandboxed**, so it can own AVPlayer and reach
///   arbitrary paths without any entitlement.
///
/// A sandboxed extension can only reach its own container, and the unsandboxed
/// host can reach anywhere — so the one directory both can agree on is the
/// extension's container. The host writes into it; the extension reads from it.
/// Only the host ever writes, which matches the architecture: the extension
/// must stay side-effect-free.
///
/// Do not reintroduce app groups or keychain access groups unless the project
/// moves to a *paid* team with a registered capability, and re-verify that the
/// build still launches more than 7 days after signing.
final class SharedPlayerStateFileStore: SharedPlayerStateStoring {
    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "SharedPlayerStateStore")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL

    init(fileURL: URL = SharedPlayerStateFileStore.defaultFileURL()) {
        self.fileURL = fileURL
        let processName = ProcessInfo.processInfo.processName
        logger.log("init process=\(processName, privacy: .public) path=\(fileURL.path, privacy: .public)")
    }

    /// The state file inside the widget extension's sandbox container:
    ///
    /// ```
    /// ~/Library/Containers/<extension bundle id>/Data/
    ///     Library/Application Support/NTSWidgetHost/sharedPlayerState.json
    /// ```
    ///
    /// The home directory is read from the passwd database rather than
    /// `NSHomeDirectory()` or `FileManager.urls(for:in:)`, because both of those
    /// are redirected *into* the container for a sandboxed process. Building the
    /// container path explicitly from the real home means the host (unsandboxed,
    /// where those APIs return the real home) and the extension (sandboxed,
    /// where they return the container) compute the identical string.
    ///
    /// Inside the sandboxed extension this resolves to its own container, which
    /// the sandbox permits; from the unsandboxed host it is just another path.
    static func defaultFileURL() -> URL {
        let home: String
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = String(cString: dir)
        } else {
            home = NSHomeDirectory()
        }

        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(AppConstants.widgetExtensionBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support/NTSWidgetHost", isDirectory: true)
            .appendingPathComponent("sharedPlayerState.json", isDirectory: false)
    }

    func load() -> SharedPlayerState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.log("load no state file — returning .idle()")
            return .idle()
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            logger.error("load read failed path=\(self.fileURL.path, privacy: .public)")
            return .idle()
        }

        guard let state = try? decoder.decode(SharedPlayerState.self, from: data) else {
            logger.error("load decode failed bytes=\(data.count, privacy: .public)")
            return .idle()
        }

        logger.log("load ok bytes=\(data.count, privacy: .public) isPlaying=\(state.isPlaying, privacy: .public) status=\(state.statusText, privacy: .public) station=\(state.currentStation?.rawValue ?? "nil", privacy: .public)")
        return state
    }

    func save(_ state: SharedPlayerState) {
        guard let data = try? encoder.encode(state) else {
            logger.error("save encode failed")
            return
        }

        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("save mkdir failed error=\(error.localizedDescription, privacy: .public)")
            return
        }

        do {
            // `.atomic` writes a temporary file and renames it into place, so a
            // concurrent reader in the other process sees either the old state
            // or the new one, never a truncated file.
            try data.write(to: fileURL, options: .atomic)
            logger.log("save ok bytes=\(data.count, privacy: .public) isPlaying=\(state.isPlaying, privacy: .public) status=\(state.statusText, privacy: .public) station=\(state.currentStation?.rawValue ?? "nil", privacy: .public)")
        } catch {
            logger.error("save write failed error=\(error.localizedDescription, privacy: .public)")
        }
    }
}
