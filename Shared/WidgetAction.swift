import Foundation

/// A widget control action, encoded as a URL the host app can be opened with.
///
/// ## Why URLs instead of App Intents
///
/// The widget buttons used to be `Button(intent:)` with `openAppWhenRun = true`.
/// That path is unavailable to this project: performing an App Intent requires
/// the app to reach `com.apple.linkd.mediator` over XPC, and `linkd` refuses
/// that connection for an app with no code-signing identity. Giving the app an
/// identity means shipping `com.apple.application-identifier` and
/// `com.apple.developer.team-identifier`, which are restricted entitlements —
/// without a valid provisioning profile AMFI SIGKILLs the process on launch,
/// and this project's free team can only issue 7-day profiles. Verified on
/// macOS 26.6.2: with those entitlements and no profile the host exits 137
/// immediately; without them it runs, but every widget tap dies inside App
/// Intents with `Unable to get synchronousRemoteObjectProxy … linkd.mediator`
/// and `perform()` is never called.
///
/// Widget `Link` destinations are opened through LaunchServices instead, which
/// needs no code identity and no entitlement, so it keeps working indefinitely.
enum WidgetAction: Equatable {
    case play(Station)
    case toggle

    private enum Host: String {
        case play
        case toggle
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = AppConstants.urlScheme

        switch self {
        case .play(let station):
            components.host = Host.play.rawValue
            components.queryItems = [URLQueryItem(name: "station", value: station.rawValue)]
        case .toggle:
            components.host = Host.toggle.rawValue
        }

        guard let url = components.url else {
            // Unreachable: every case above produces a valid scheme + host.
            preconditionFailure("failed to build widget action URL")
        }

        return url
    }

    init?(url: URL) {
        guard url.scheme == AppConstants.urlScheme,
              let host = url.host.flatMap(Host.init(rawValue:)) else {
            return nil
        }

        switch host {
        case .toggle:
            self = .toggle
        case .play:
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "station" }?
                .value
            guard let raw, let station = Station(rawValue: raw) else {
                return nil
            }
            self = .play(station)
        }
    }
}
