import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif
#if os(macOS)
import AppKit
#endif

protocol WidgetReloading {
    func reloadTimelines()
}

struct WidgetReloader: WidgetReloading {
    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "WidgetReloader")

    func reloadTimelines() {
        #if canImport(WidgetKit)
        logger.log("reloadTimelines requested kind=\(AppConstants.widgetKind, privacy: .public)")
        // Fire only one reload. `reloadAllTimelines()` on top causes chronod
        // to dedupe and schedule provider runs LATER, not sooner.
        WidgetCenter.shared.reloadTimelines(ofKind: AppConstants.widgetKind)
        #endif
    }
}

enum PlaybackStateSignal {
    static let notificationName = Notification.Name("com.fede.NTSWidgetHost.playbackStateDidChange")

    static func post() {
        #if os(macOS)
        DistributedNotificationCenter.default().post(
            name: notificationName,
            object: nil,
            userInfo: nil
        )
        #endif
    }

    static func addObserver(using block: @escaping () -> Void) -> NSObjectProtocol? {
        #if os(macOS)
        return DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { _ in
            block()
        }
        #else
        return nil
        #endif
    }

    static func removeObserver(_ token: NSObjectProtocol?) {
        #if os(macOS)
        if let token {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        #endif
    }
}
