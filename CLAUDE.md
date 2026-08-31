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

# Run unit tests
xcodebuild -project NTSWidgetHost.xcodeproj -scheme NTSWidgetHost \
  -destination 'platform=macOS' test

# Package a distributable Release zip (handles DEVELOPER_DIR itself)
./scripts/package-release.sh 1.0.2
./scripts/package-release.sh 1.0.2 --publish   # + gh release create/upload
```

Run a single test with `-only-testing:NTSWidgetHostTests/<Class>/<method>`. The test target builds against the host app via `TEST_HOST`/`BUNDLE_LOADER`, and `@testable import` needs `ENABLE_TESTABILITY`, which the project-level Debug config sets.

### Verifying the installed widget

Xcode rebuilds are *not* enough — the desktop widget can keep running stale code and a stale copy from `/Applications`:

```bash
rm -rf "/Applications/NTS Radio.app"
ditto dist/stage/"NTS Radio.app" "/Applications/NTS Radio.app"
# Replacing the bundle DEREGISTERS the extension — pluginkit will report no
# match and the widget stays blank until LaunchServices re-registers it.
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R "/Applications/NTS Radio.app"
pluginkit -m -i com.fede.NTSWidgetHost.NTSWidgetExtension -vvv   # must print the extension
killall NTSWidgetExtension NTSWidgetHost NotificationCenter chronod
open -a "/Applications/NTS Radio.app"   # must succeed; a spawn failure means an entitlement problem
```

Two diagnostics worth knowing, both learned the hard way:

- `open -a` failing with `Launchd job spawn failed` / POSIX 163 means AMFI rejected the code signature — almost always a profile-dependent entitlement (see signing invariants), not a UI bug. A blank black widget is the user-visible symptom.
- **`log show` does not reliably persist this app's `Logger` output on macOS 26** — it can return zero lines for a process that is demonstrably running, so absence of logs proves nothing. Use `log stream` while reproducing, or check `pgrep -fl "NTS Radio.app"` to confirm the host and extension are actually alive.

`MANUAL_TEST_PLAN.md` is the manual acceptance checklist (widget add, station switch, pause/resume, offline failure path).

## Architecture

Three targets share one source tree: `Shared/` compiles into both the host app and the extension; `NTSWidgetHost/` is host-only (playback); `NTSWidgetExtension/` is the widget UI.

### Process split — the central constraint

**All audio playback lives in the host app process. The widget extension must never own AVPlayer, network, or state writes.**

- **Widget controls are `Link(destination:)` to `ntsradio://` URLs, not App Intents.** A tap goes through LaunchServices, launches the hidden host if needed, and is handled by `WidgetActionURLHandler` (an `NSApplicationDelegate` on the host), which calls `RadioPlayerService`. `WidgetAction` in `Shared/` encodes and parses those URLs, and the scheme is declared in `NTSWidgetHost/Info.plist` — the two must stay in sync or taps silently do nothing.

  This is not a style choice. App Intents cannot work in this build: performing one needs an XPC connection to `com.apple.linkd.mediator`, and `linkd` refuses it for an app with no code-signing identity — the tap dies with `Unable to get synchronousRemoteObjectProxy` and `perform()` is never called. Acquiring an identity means shipping restricted entitlements, which AMFI SIGKILLs (exit 137) without a valid profile, and this team's profiles last 7 days. Both verified on macOS 26.6.2. `PlayStationIntent` / `TogglePlaybackIntent` still exist and are still host-routed, but **nothing invokes them**; they would only become usable on a paid team.

  A consequence worth knowing: an `NSApplicationDelegate` is required rather than SwiftUI's `onOpenURL`, because the app's only scene is `Settings`, which is never instantiated while it runs headless.
- The host is headless: `LSUIElement = YES` plus `NSApplication.setActivationPolicy(.accessory)`, so no Dock icon or window. `ContentView` exists but is not presented (scene is `Settings { EmptyView() }`).
- `PlaybackControllerLocator.controller` defaults to `HostRequiredPlaybackController`, which deliberately does nothing but re-read shared state and log an error. `NTSWidgetHostApp.init` swaps in `RadioPlayerService.shared`. If an intent ever executes in the extension, it fails inertly instead of trying to stream audio in a transient WidgetKit process.
- The extension entitlements intentionally omit `com.apple.security.network.client`.

`NTSWidgetProvider` must stay side-effect-free: `getSnapshot` returns a static idle entry immediately (gallery/drag-add stability), `getTimeline` only reads shared state. Adding network fetches, state writes, AVPlayer, or infinite animations to provider/render paths has previously frozen the widget sidebar / Notification Center hard enough to require a system restart.

### Signing invariants — read before touching entitlements

This project is signed by a **free** Apple team, whose provisioning profiles last **7 days**. Any *profile-dependent* entitlement therefore becomes a time bomb: once the profile expires, AMFI refuses to spawn the process, `open` fails with `Launchd job spawn failed` (POSIX 163), and the widget renders as an **empty black rectangle**. This is exactly how 1.0.1 broke — built 2026-07-28, profile expired 2026-08-04, dead for every downloader a week later.

The rules that follow, all verified on macOS 26.6.2:

- **Never ship `com.apple.application-identifier`, `com.apple.developer.team-identifier`, `keychain-access-groups`, or `com.apple.security.application-groups`**, and never embed a `embedded.provisionprofile`. `package-release.sh` fails the build if any of them survive.
- **The widget extension must keep `com.apple.security.app-sandbox`.** macOS refuses to register an unsandboxed app extension — `pluginkit -m -i com.fede.NTSWidgetHost.NTSWidgetExtension` reports no match and the widget never loads. Plain `app-sandbox` needs no profile, so it is expiry-safe.
- **The host app is deliberately unsandboxed** (empty entitlements). That is what lets it reach into the extension's container, and it needs no entitlement for network or AVPlayer.
- Signing is `CODE_SIGN_STYLE = Manual` with `CODE_SIGN_IDENTITY = "-"` (ad-hoc) and an empty `DEVELOPMENT_TEAM`, so Xcode never fetches a profile.

Only revisit this if the project moves to a *paid* team with a registered capability — and then verify the build still launches more than 7 days after signing.

### Shared state transport is a file in the extension's container

`SharedPlayerStateFileStore` keeps the JSON-encoded `SharedPlayerState` at:

```
~/Library/Containers/com.fede.NTSWidgetHost.NTSWidgetExtension/Data/
    Library/Application Support/NTSWidgetHost/sharedPlayerState.json
```

The two processes are asymmetric, and that asymmetry picks the path: the extension is sandboxed so it can only reach its own container, while the unsandboxed host can reach anywhere. The extension's container is therefore the only directory both can agree on. **The host writes; the extension only reads** — which is also required by the side-effect-free provider rule below.

The home directory is resolved from the **passwd database**, not `NSHomeDirectory()` or `FileManager.urls(for:in:)`. Those are redirected into the container inside a sandboxed process, so using them would make the extension compute a doubled container path and silently read a different file than the host wrote.

Every sandbox-scoped alternative (app groups, team-prefixed keychain access groups, `UserDefaults(suiteName:)`) needs a profile-dependent entitlement, so none of them are available here.

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
- URL scheme `ntsradio` (`AppConstants.urlScheme`), declared in `NTSWidgetHost/Info.plist` under `CFBundleURLTypes`; the host target uses that explicit plist (not `GENERATE_INFOPLIST_FILE`) because `CFBundleURLTypes` cannot be expressed as an `INFOPLIST_KEY_*` setting
- The extension bundle id also names the sandbox container the shared state file lives in, so `AppConstants.widgetExtensionBundleIdentifier` must match the extension target's `PRODUCT_BUNDLE_IDENTIFIER`
- No team id is set anywhere; builds are ad-hoc signed on purpose (see signing invariants)
- Distribution app is renamed **NTS Radio** at package time; bundle id is unchanged

## Docs

`NTS_WIDGET_WORKFLOW.md` is a chronological decision log **including superseded decisions** — entries are marked `Status: Superseded`, so read dates and status before treating one as current. `LLM_PROJECT_HANDOFF.md` is the architecture snapshot and should be updated after architecture changes.
