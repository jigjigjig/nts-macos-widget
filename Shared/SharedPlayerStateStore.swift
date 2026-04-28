import Foundation
import Security
import os

protocol SharedPlayerStateStoring {
    func load() -> SharedPlayerState
    func save(_ state: SharedPlayerState)
}

/// Shared state store for the widget and host app.
///
/// ## Why the Keychain, not an app-group file or UserDefaults suite?
///
/// The project is signed with a development cert whose provisioning profile
/// does NOT authorize `com.apple.security.application-groups` (the App Group
/// capability has not been registered with Apple for this team). When that
/// happens, both processes appear to see the same group container path at
/// `~/Library/Group Containers/<group>/…`, but the sandbox silently treats
/// each process' view as private — writes from one side are not readable
/// from the other. The same applies to `UserDefaults(suiteName:)` because
/// cfprefsd stamps the backing plist with a `com.apple.quarantine` xattr
/// that blocks cross-sandbox reads.
///
/// The provisioning profiles do, however, authorize `keychain-access-groups`
/// with the team prefix (`CUD2M2N848.*`). Team-shared keychain items work
/// reliably for sharing small amounts of state between a host app and its
/// extensions without requiring the App Group capability to be registered.
/// That is what we use here — a single generic-password item storing the
/// JSON-encoded `SharedPlayerState`.
final class AppGroupSharedPlayerStateStore: SharedPlayerStateStoring {
    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "SharedPlayerStateStore")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Account label (must be identical in both processes).
    private let account = "sharedPlayerState"

    // Shared keychain access group. Must match `keychain-access-groups` in
    // the provisioning profile. `CUD2M2N848` is the development team ID.
    // The suffix is arbitrary but must be consistent across host + extension.
    private let accessGroup: String

    init(appGroupIdentifier: String = AppConstants.appGroupIdentifier) {
        accessGroup = "CUD2M2N848.com.fede.NTSWidgetHost.sharedstate"
        let processName = ProcessInfo.processInfo.processName
        logger.log("init process=\(processName, privacy: .public) accessGroup=\(self.accessGroup, privacy: .public)")
    }

    private func baseQuery() -> [String: Any] {
        // `kSecUseDataProtectionKeychain = true` selects the modern, iOS-style
        // data-protection keychain instead of the legacy file-based login
        // keychain. The data-protection keychain uses `kSecAttrAccessGroup`
        // from signed entitlements for sharing, and does NOT use per-app ACLs
        // (which are what cause the "NTSWidgetExtension wants to use your
        // confidential information…" prompt on the legacy keychain).
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    func load() -> SharedPlayerState {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue as Any
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            logger.log("load no keychain item — returning .idle()")
            return .idle()
        }

        guard status == errSecSuccess else {
            logger.error("load SecItemCopyMatching failed status=\(status, privacy: .public)")
            return .idle()
        }

        guard let data = result as? Data else {
            logger.error("load result was not Data")
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

        let query = baseQuery()
        let update: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if updateStatus == errSecSuccess {
            logger.log("save updated existing bytes=\(data.count, privacy: .public) isPlaying=\(state.isPlaying, privacy: .public) status=\(state.statusText, privacy: .public) station=\(state.currentStation?.rawValue ?? "nil", privacy: .public)")
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                logger.log("save added new bytes=\(data.count, privacy: .public) isPlaying=\(state.isPlaying, privacy: .public) status=\(state.statusText, privacy: .public) station=\(state.currentStation?.rawValue ?? "nil", privacy: .public)")
            } else {
                logger.error("save SecItemAdd failed status=\(addStatus, privacy: .public)")
            }
            return
        }

        logger.error("save SecItemUpdate failed status=\(updateStatus, privacy: .public)")
    }
}
