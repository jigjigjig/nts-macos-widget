import SwiftUI
import WidgetKit
import os

struct NTSWidgetEntry: TimelineEntry {
    let date: Date
    let state: SharedPlayerState
}

struct NTSWidgetProvider: TimelineProvider {
    private let stateStore = AppGroupSharedPlayerStateStore()
    private let metadataService: NTSLiveMetadataFetching = NTSLiveMetadataService()
    private let logger = Logger(subsystem: "com.fede.NTSWidgetHost", category: "NTSWidgetProvider")

    func placeholder(in context: Context) -> NTSWidgetEntry {
        logger.log("placeholder called")
        return NTSWidgetEntry(date: .now, state: .idle())
    }

    func getSnapshot(in context: Context, completion: @escaping (NTSWidgetEntry) -> Void) {
        let loaded = stateStore.load()
        logger.log("getSnapshot isPlaying=\(loaded.isPlaying, privacy: .public) status=\(loaded.statusText, privacy: .public) station=\(loaded.currentStation?.rawValue ?? "nil", privacy: .public)")
        completion(NTSWidgetEntry(date: .now, state: loaded))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NTSWidgetEntry>) -> Void) {
        Task {
            var loaded = stateStore.load()
            logger.log("getTimeline isPlaying=\(loaded.isPlaying, privacy: .public) status=\(loaded.statusText, privacy: .public) station=\(loaded.currentStation?.rawValue ?? "nil", privacy: .public) updatedAt=\(loaded.updatedAt.timeIntervalSince1970, privacy: .public)")

            loaded = await mergeMetadata(into: loaded)

            let now = Date.now
            var entries: [NTSWidgetEntry] = [NTSWidgetEntry(date: now, state: loaded)]

            // Key trick: provide PRE-SCHEDULED future entries so WidgetKit can
            // render transitions locally WITHOUT calling back into the provider.
            // This avoids dependence on chronod, which can delay provider runs by
            // many seconds under budget pressure.
            if loaded.isPlaying, loaded.statusText.hasPrefix("Connecting"),
               let station = loaded.currentStation {
                var optimisticPlaying = loaded
                optimisticPlaying.currentStation = station
                optimisticPlaying.isPlaying = true
                optimisticPlaying.statusText = "Playing \(station.displayName)"
                optimisticPlaying.lastError = nil
                optimisticPlaying.updatedAt = now.addingTimeInterval(3)

                entries.append(
                    NTSWidgetEntry(
                        date: now.addingTimeInterval(3),
                        state: optimisticPlaying
                    )
                )
            }

            // Next full refresh well in the future — we rely on explicit
            // reloadTimelines for state changes. A long window conserves the
            // per-widget reload budget.
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now)
                ?? now.addingTimeInterval(30 * 60)

            completion(Timeline(entries: entries, policy: .after(nextRefresh)))
        }
    }

    private func mergeMetadata(into state: SharedPlayerState) async -> SharedPlayerState {
        do {
            let nowPlaying = try await metadataService.fetchNowPlaying()
            let updated = state.merged(with: nowPlaying)
            if updated != state {
                stateStore.save(updated)
            }
            return updated
        } catch {
            logger.debug("metadata fetch skipped error=\(error.localizedDescription, privacy: .public)")
            return state
        }
    }
}

struct NTSWidgetEntryView: View {
    let entry: NTSWidgetEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            TopRow(status: status)
            Spacer(minLength: 0)
            StatusLine(status: status)
            Spacer(minLength: 0)
            ControlRow(status: status)
        }
        .padding(.top, 18)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: surfaceGradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var status: WidgetStatus {
        WidgetStatus(state: entry.state)
    }

    private var surfaceGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.122, green: 0.122, blue: 0.133),
                Color(red: 0.094, green: 0.094, blue: 0.106)
            ]
        }

        return [
            Color(red: 0.992, green: 0.992, blue: 0.988),
            Color(red: 0.965, green: 0.961, blue: 0.949)
        ]
    }
}

private struct ControlRow: View {
    let status: WidgetStatus
    private let spacing: CGFloat = 8
    private let stationWeight: CGFloat = 1
    private let playWeight: CGFloat = 1.25

    var body: some View {
        GeometryReader { proxy in
            let totalSpacing = spacing * 2
            let availableWidth = max(proxy.size.width - totalSpacing, 0)
            let unit = availableWidth / (stationWeight + stationWeight + playWeight)

            HStack(spacing: spacing) {
                StationButton(station: .nts1, status: status)
                    .frame(width: unit * stationWeight)
                StationButton(station: .nts2, status: status)
                    .frame(width: unit * stationWeight)
                PlayPauseButton(status: status)
                    .frame(width: unit * playWeight)
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(height: 44)
    }
}

private struct TopRow: View {
    let status: WidgetStatus

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("NTS")
                    .font(.system(size: 13, weight: .bold, design: .default))
                    .tracking(0.6)
                    .textCase(.uppercase)

                Text("Radio")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .tracking(0.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Badge(status: status)
        }
    }
}

private struct Badge: View {
    let status: WidgetStatus

    var body: some View {
        HStack(spacing: 4) {
            if status.visualState == .playing {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7, weight: .bold, design: .default))
            } else if status.visualState == .connecting {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 8, weight: .bold, design: .default))
            }

            Text(status.badgeText)
                .font(.system(size: 10.5, weight: .semibold, design: .default))
                .tracking(0.4)
                .textCase(.uppercase)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(background))
    }

    private var foreground: Color {
        switch status.visualState {
        case .playing:
            return .red
        case .connecting:
            return .orange
        default:
            return .secondary
        }
    }

    private var background: Color {
        switch status.visualState {
        case .playing:
            return .red.opacity(0.12)
        case .connecting:
            return .orange.opacity(0.14)
        case .idle:
            return .secondary.opacity(0.08)
        default:
            return .secondary.opacity(0.12)
        }
    }
}

private struct StatusLine: View {
    let status: WidgetStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            symbol

            Text(status.lineText)
                .font(.system(size: 22, weight: .semibold, design: .default))
                .tracking(-0.5)
                .foregroundStyle(status.visualState == .paused || status.visualState == .idle ? .secondary : .primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var symbol: some View {
        switch status.visualState {
        case .idle:
            Image(systemName: "circle.fill")
                .font(.system(size: 6, weight: .regular, design: .default))
                .foregroundStyle(idleDot)
        case .connecting:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(.orange)
        case .playing:
            Image(systemName: "circle.fill")
                .font(.system(size: 7, weight: .bold, design: .default))
                .foregroundStyle(.red)
        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(.secondary)
        case .unavailable:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(.orange)
        }
    }

    private var idleDot: Color {
        #if canImport(AppKit)
        return Color(nsColor: .tertiaryLabelColor)
        #else
        return .secondary
        #endif
    }
}

private struct StationButton: View {
    let station: Station
    let status: WidgetStatus
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(intent: PlayStationIntent(station: station)) {
            HStack(spacing: 5) {
                if isActive {
                    WaveformIcon(color: .accentColor)
                        .frame(width: 12, height: 10)
                        .accessibilityHidden(true)
                }

                Text(station.badgeLabel)
                    .font(.system(size: 15, weight: isActive ? .semibold : .medium, design: .default))
                    .tracking(-0.1)
            }
            .foregroundStyle(isActive ? .primary : .secondary)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(background)
        .overlay(stroke)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: isActive ? .black.opacity(0.12) : .clear, radius: 3, y: 2)
        .shadow(color: isActive ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
        .accessibilityLabel("NTS \(station.badgeLabel)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var isActive: Bool {
        switch status.visualState {
        case .playing, .paused, .connecting:
            return status.station == station
        default:
            return false
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(stationFill)
    }

    private var stationFill: AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: activeStationGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        return AnyShapeStyle(inactiveStationBackground)
    }

    private var stroke: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(strokeColor, lineWidth: 0.5)
    }

    private var strokeColor: Color {
        if colorScheme == .dark {
            return .white.opacity(isActive ? 0.20 : 0.26)
        }

        return .black.opacity(isActive ? 0.08 : 0.10)
    }

    private var activeStationGradient: [Color] {
        if colorScheme == .dark {
            return [
                Color.white.opacity(0.18),
                Color.white.opacity(0.08)
            ]
        }

        return [
            .white,
            Color(red: 0.957, green: 0.953, blue: 0.937)
        ]
    }

    private var inactiveStationBackground: Color {
        if colorScheme == .dark {
            return .white.opacity(0.12)
        }

        #if canImport(AppKit)
        return Color(nsColor: .quaternaryLabelColor).opacity(0.08)
        #else
        return .secondary.opacity(0.08)
        #endif
    }
}

private struct PlayPauseButton: View {
    let status: WidgetStatus

    var body: some View {
        Button(intent: TogglePlaybackIntent()) {
            HStack(spacing: 6) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold, design: .default))

                Text(isPlaying ? "Pause" : "Play")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .tracking(-0.1)
            }
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(status.visualState == .unavailable ? tertiaryForeground : .white)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(status.visualState == .unavailable ? .black.opacity(0.10) : .clear, lineWidth: 0.5)
        )
        .shadow(color: status.visualState == .unavailable ? .clear : .accentColor.opacity(0.35), radius: 4, y: 2)
        .disabled(status.visualState == .unavailable)
        .accessibilityLabel(isPlaying ? "Pause NTS \(status.station.badgeLabel)" : "Play NTS \(status.station.badgeLabel)")
    }

    private var isPlaying: Bool {
        status.visualState == .playing || status.visualState == .connecting
    }

    private var background: AnyShapeStyle {
        if status.visualState == .unavailable {
            return AnyShapeStyle(Color.secondary.opacity(0.12))
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [.accentColor, .accentColor.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var tertiaryForeground: Color {
        #if canImport(AppKit)
        return Color(nsColor: .tertiaryLabelColor)
        #else
        return .secondary
        #endif
    }
}

private struct WaveformIcon: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0
    private let heights: [CGFloat] = [0.4, 0.9, 1.0, 0.9, 0.4]

    var body: some View {
        HStack(spacing: 1.6) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 1.6, height: 10)
                    .scaleEffect(y: animatedHeight(index), anchor: .center)
                    .animation(
                        reduceMotion
                        ? .default
                        : .easeInOut(duration: 0.9)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.08),
                        value: phase
                    )
            }
        }
        .onAppear {
            if !reduceMotion {
                phase = 1
            }
        }
    }

    private func animatedHeight(_ index: Int) -> CGFloat {
        if reduceMotion {
            return heights[index]
        }

        return phase == 1 ? (index.isMultiple(of: 2) ? 1.0 : 0.5) : heights[index] * 0.4
    }
}

private struct WidgetStatus {
    let station: Station
    let visualState: VisualState
    let nowTitle: String?

    enum VisualState {
        case idle
        case connecting
        case playing
        case paused
        case unavailable
    }

    init(state: SharedPlayerState) {
        let selectedStation = state.currentStation ?? .nts1
        station = selectedStation
        nowTitle = state.nowTitle(for: selectedStation)

        if let error = state.lastError, !error.isEmpty {
            visualState = .unavailable
            return
        }

        if state.statusText == "Unavailable" {
            visualState = .unavailable
            return
        }

        if state.isPlaying {
            if state.statusText.hasPrefix("Connecting") {
                visualState = .connecting
            } else {
                visualState = .playing
            }
            return
        }

        if state.currentStation != nil {
            visualState = .paused
            return
        }

        visualState = .idle
    }

    var lineText: String {
        switch visualState {
        case .idle:
            return "Not playing"
        case .connecting:
            return "Connecting \(station.displayName)…"
        case .playing:
            return nowTitle ?? "Playing \(station.displayName)"
        case .paused:
            return "Paused"
        case .unavailable:
            return "Unavailable"
        }
    }

    var badgeText: String {
        switch visualState {
        case .idle:
            return "Ready"
        case .connecting:
            return "Loading · \(station.badgeLabel)"
        case .playing:
            return "Live · \(station.badgeLabel)"
        case .paused:
            return station.displayName
        case .unavailable:
            return "Offline"
        }
    }
}

struct NTSWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppConstants.widgetKind, provider: NTSWidgetProvider()) { entry in
            NTSWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("NTS Live (Host)")
        .description("Play NTS 1 and NTS 2 live streams.")
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
        .supportedFamilies([.systemMedium])
    }
}

#Preview("Idle", as: .systemMedium) {
    NTSWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: nil,
            isPlaying: false,
            statusText: "Paused",
            lastError: nil,
            updatedAt: .now
        )
    )
}

#Preview("NTS 1 Playing", as: .systemMedium) {
    NTSWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: .nts1,
            isPlaying: true,
            statusText: "Playing NTS 1",
            lastError: nil,
            updatedAt: .now
        )
    )
}

#Preview("NTS 2 Playing", as: .systemMedium) {
    NTSWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: .nts2,
            isPlaying: true,
            statusText: "Playing NTS 2",
            lastError: nil,
            updatedAt: .now
        )
    )
}

#Preview("Paused", as: .systemMedium) {
    NTSWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: .nts1,
            isPlaying: false,
            statusText: "Paused",
            lastError: nil,
            updatedAt: .now
        )
    )
}

#Preview("Unavailable", as: .systemMedium) {
    NTSWidget()
} timeline: {
    NTSWidgetEntry(
        date: .now,
        state: SharedPlayerState(
            currentStation: .nts1,
            isPlaying: false,
            statusText: "Unavailable",
            lastError: "Network unavailable",
            updatedAt: .now
        )
    )
}
