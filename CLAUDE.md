# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A native macOS app (`NTSWidgetHost`) plus WidgetKit extension (`NTSWidgetExtension`) that plays the NTS 1 / NTS 2 live streams from a `systemMedium` desktop widget. macOS 14+. Unofficial fan project.

**Scope is deliberately locked (v1):** one widget family (`systemMedium`), two stations, three controls (`1`, `2`, `Play/Pause`), one status line. No artwork, no search, no menu bar UI, no extra widget sizes. Don't expand this without being asked.

## Commands

`xcode-select` on this machine points at CommandLineTools, so **every `xcodebuild` invocation needs `DEVELOPER_DIR`**:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Build host + embedded extension
xcodebuild -project NTSWidgetHost.xcodeproj -scheme NTSWidgetHost -configuration Debug build

# Run unit tests (see caveat below)
xcodebuild -project NTSWidgetHost.xcodeproj -scheme NTSWidgetHost \
  -destination 'platform=macOS' test

# Package a distributable Release zip (handles DEVELOPER_DIR itself)
./scripts/package-release.sh 1.0.1
./scripts/package-release.sh 1.0.1 --publish   # + gh release create/upload
```

**Test caveat:** the shared `NTSWidgetHost.xcscheme` has an empty `<TestAction>` with no `TestableReference`, so `xcodebuild test` currently builds and runs nothing. To run tests you must add the testable to the scheme (in Xcode: Product → Scheme → Edit Scheme → Test → add `NTSWidgetHostTests`) or invoke the test target directly with `-only-testing:NTSWidgetHostTests/<Class>/<method>` after wiring it up. Test target uses `TEST_HOST`/`BUNDLE_LOADER` against the host app, so it must be built with the host.

### Verifying the installed widget

Xcode rebuilds are *not* enough — the desktop widget can keep running stale code and a stale copy from `/Applications`:

```bash
ditto build/DerivedData/Build/Products/Debug/NTSWidgetHost.app /Applications/NTSWidgetHost.app
killall NTSWidgetExtension NTSWidgetHost NotificationCenter
log show --last 20m --predicate 'subsystem == "com.fede.NTSWidgetHost"' --style compact
```

All runtime logging uses subsystem `com.fede.NTSWidgetHost` with per-type categories; that log predicate is the primary debugging tool for this project.

`MANUAL_TEST_PLAN.md` is the manual acceptance checklist (widget add, station switch, pause/resume, offline failure path).

## Architecture

Three targets share one source tree: `Shared/` compiles into both the host app and the extension; `NTSWidgetHost/` is host-only (playback); `NTSWidgetExtension/` is the widget UI.

### Process split — the central constraint

**All audio playback lives in the host app process. The widget extension must never own AVPlayer, network, or state writes.**

- Both intents (`PlayStationIntent`, `TogglePlaybackIntent`) set `openAppWhenRun = true` so tapping a widget button launches the hidden host if needed and executes there.
- The host is headless: `LSUIElement = YES` plus `NSApplication.setActivationPolicy(.accessory)`, so no Dock icon or window. `ContentView` exists but is not presented (scene is `Settings { EmptyView() }`).
- `PlaybackControllerLocator.controller` defaults to `HostRequiredPlaybackController`, which deliberately does nothing but re-read shared state and log an error. `NTSWidgetHostApp.init` swaps in `RadioPlayerService.shared`. If an intent ever executes in the extension, it fails inertly instead of trying to stream audio in a transient WidgetKit process.
- The extension entitlements intentionally omit `com.apple.security.network.client`.

`NTSWidgetProvider` must stay side-effect-free: `getSnapshot` returns a static idle entry immediately (gallery/drag-add stability), `getTimeline` only reads shared state. Adding network fetches, state writes, AVPlayer, or infinite animations to provider/render paths has previously frozen the widget sidebar / Notification Center hard enough to require a system restart.

### Shared state transport is the Keychain, not App Groups

`AppGroupSharedPlayerStateStore` (name is historical) stores the JSON-encoded `SharedPlayerState` in a **data-protection keychain generic-password item** under access group `$(AppIdentifierPrefix)com.fede.NTSWidgetHost.sharedstate`.

Reason: the signing profile does not authorize the App Group capability, so app-group container files and `UserDefaults(suiteName:)` silently diverge between the two sandboxes (each process sees its own private view). `keychain-access-groups` with the team prefix does work. `kSecUseDataProtectionKeychain = true` is required — the legacy keychain would trigger per-app ACL consent prompts from the extension. Don't "fix" this back to an app-group file without first registering the App Group capability with Apple.

### Playback state machine

`RadioPlayerService` (host, `@MainActor`) owns `AVPlayerEngine` and is the only writer of shared state.

- `AVPlayerEngine` publishes `RadioEngineState` (`idle/connecting/playing/paused/failed`) via KVO on `timeControlStatus`, `rate`, and item `status`. It pauses before `replaceCurrentItem` and forces `.connecting` on load, because `timeControlStatus` can briefly report `.playing` for a freshly replaced item; `play()` deliberately does not evaluate state in the same runloop tick.
- `apply(_:)` dedupes equivalent states (ignoring `updatedAt`) before persisting and reloading. **Fire at most one widget reload per meaningful transition** — chronod budgets reloads, and bursts cause *later* provider runs, not sooner. `WidgetReloader` calls only `reloadTimelines(ofKind:)`, never also `reloadAllTimelines()`.
- On host launch, a persisted `isPlaying == true` is normalized to paused so a cold launch or rebuild never auto-starts audio.
- `NTSLiveMetadataService` (host-only, from `nts.live/api/v2/live`) is fetched only *after* playback reaches `.playing`, and merged titles avoid bumping `metadataUpdatedAt` when unchanged.
- `HostMediaControls` wires `MPRemoteCommandCenter` (play/pause/toggle, and next/previous track cycles between the two stations) and mirrors state into `MPNowPlayingInfoCenter`.

The widget's visual layer derives a `WidgetStatus` (`idle`, `playing`, `paused`, `unavailable`) from `SharedPlayerState`: `lastError` present or `statusText == "Unavailable"` → unavailable; `isPlaying` → playing; station set but not playing → paused; else idle.

### Widget layout invariants

`.containerBackgroundRemovable(false)` and `.contentMarginsDisabled()` are on the widget configuration to stop the desktop/vibrant rendering path from replacing the custom gradient background and drifting the margins. The control row uses a weighted `GeometryReader` (`1 : 1 : 1.25`) rather than a flexible `HStack`, because the flexible layout let the play button expand and collapse the station buttons at runtime. Dark-mode inactive station fills/strokes are intentionally higher-contrast than they look "correct" in previews — vibrancy washes them out on the real desktop.

## Identifiers

- App bundle id `com.fede.NTSWidgetHost`; extension `com.fede.NTSWidgetHost.NTSWidgetExtension`
- Widget kind `NTSWidget` (`AppConstants.widgetKind`); the extension scheme sets `_XCWidgetKind=NTSWidget`
- Team `CUD2M2N848`; the keychain access-group string in `SharedPlayerStateStore.swift` hardcodes this prefix
- Distribution app is renamed **NTS Radio** at package time; bundle id is unchanged

## Docs

`NTS_WIDGET_WORKFLOW.md` is a chronological decision log **including superseded decisions** — entries are marked `Status: Superseded`, so read dates and status before treating one as current. `LLM_PROJECT_HANDOFF.md` is the architecture snapshot and should be updated after architecture changes.
