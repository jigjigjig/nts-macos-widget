import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
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
