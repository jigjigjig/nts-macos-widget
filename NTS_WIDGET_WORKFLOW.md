# NTS Widget v1 Workflow

## Stream Playback Regression Fix (2026-04-20)

### Problem observed

- Widget state transitions were visible, but no stream audio played.
- Runtime inspection showed no persistent `NTSWidgetHost` process during widget interaction, so state-only intents had no playback owner to execute AVPlayer.

### Root-cause decisions

### 1) Restore direct playback execution in intents

- Decision: `PlayStationIntent` and `TogglePlaybackIntent` now call `PlaybackControllerLocator.controller` directly again.
- Why: Intent execution must trigger real playback in the same process path that handles the widget action; state-only writes are insufficient if host process is not alive.

### 2) Keep widget-first interaction (no host window/app opening)

- Decision: Set `openAppWhenRun = false` for both widget intents.
- Why: This preserves widget-only controls and prevents user-visible host app launches while still executing playback.

### 3) Remove app-group defaults touchpoints in extension hot path

- Decision: In app-group-container mode, `SharedPlayerStateStore` no longer initializes suite `UserDefaults` and relies on file-backed JSON + legacy plist migration.
- Why: Avoid repeated `CFPrefs` sandbox read warnings in extension timeline/intent runtime and keep state transport deterministic.

## Runtime Mismatch Triage (2026-04-19)

### Problem observed on installed desktop widget

- Installed widget did not visually match previews/spec:
  - custom surface styling looked replaced by desktop-vibrant treatment
  - station controls were not reliably visible in the bottom row
- Pressing widget controls launched/opened the host app UI, which broke the “widget-first” interaction requirement.

### Root-cause decisions

### 1) Lock widget background rendering

- Decision: Apply `.containerBackgroundRemovable(false)` on widget configuration.
- Why: Prevent the host system from stripping/replacing the custom container background in desktop contexts.

### 2) Neutralize runtime content-margin drift

- Decision: Apply `.contentMarginsDisabled()` on widget configuration.
- Why: Keep layout geometry consistent with handoff spacing rather than auto margin adjustments.

### 3) Prevent control collapse with deterministic row sizing

- Decision: Replace the flexible control `HStack` with a weighted `GeometryReader` row (`1 : 1 : 1.25` for station1/station2/play).
- Why: Eliminate runtime compression where primary action expands and station buttons collapse.

### 3b) Raise dark-mode control contrast for installed widgets

- Decision: Increase inactive station background/stroke contrast in dark mode (lighter fill + light stroke).
- Why: Desktop vibrant rendering can wash out subtle dark-on-dark strokes, making station controls appear missing.

### 4) Keep playback host process but remove host UI surface

- Decision: Convert app scene to headless settings-only scene and set activation policy to `.accessory`.
- Why: Widget actions can still run playback logic without opening a visible host window, preserving widget as the sole user-facing control surface.

### 5) Force runtime reload after extension changes

- Decision: Restart `NTSWidgetExtension`, `NTSWidgetHost`, and `NotificationCenter` when installed UI appears unchanged after rebuild.
- Why: Widget processes can keep stale snapshots/code paths alive across rebuilds; process restart forces fresh extension load.

### 6) Make playback ownership explicit in widget intent runtime

- Decision: Set `PlaybackControllerLocator` default to a concrete AVPlayer-backed controller available in both app and widget extension code paths.
- Why: Widget taps execute in extension runtime and must not depend on host-app-only initialization to control playback.

### 7) Remove `AudioPlaybackIntent` conformance from widget controls

- Decision: Keep intents as plain `AppIntent` for deterministic widget action execution.
- Why: This avoids media-intent routing behavior that can obscure station/play state transitions from direct widget interactions.

### 8) Give extension explicit network capability

- Decision: Add `com.apple.security.network.client` to extension entitlements.
- Why: Stream playback can be initiated by extension-owned intent handling and must be allowed to open network streams.

### 9) Restore explicit App Group entitlement on both targets

- Decision: Add `com.apple.security.application-groups = group.com.fede.NTSWidgetHost` to both host-app and widget-extension entitlements.
- Why: Widget intents and timeline updates can execute in different processes; without a shared app-group store, state writes/read diverge and UI remains stuck at idle.

### 10) Replace group `UserDefaults` as primary state transport with file-backed app-group storage

- Decision: Persist `SharedPlayerState` to a JSON file under `App Group container/Library/Application Support/sharedPlayerState.json` and use `UserDefaults` only as fallback.
- Why: Widget runtime logs showed cfprefsd sandbox read failures for the group defaults domain in extension context; direct file I/O in the resolved app-group container is reliable across timeline + intent processes.

### 11) Add legacy-state migration path

- Decision: When the JSON state file is missing, load and decode legacy state from `App Group container/Library/Preferences/group.com.fede.NTSWidgetHost.plist`, then seed the new JSON file.
- Why: Existing installs may already have valid state in old preferences storage and should not regress to idle on first launch after store migration.

### 12) Move actual stream playback ownership back to host app process

- Decision: Widget intents wrote desired playback state and broadcast a distributed signal; host app observed that signal and executed AVPlayer actions.
- Why: Widget extension runtime is transient and not a durable place for continuous audio streaming; host process is stable while the widget remains the sole user-facing control surface.
- Status: Superseded by 2026-04-20 direct intent playback after host process liveness regression in production usage.

### 13) Launch host process on widget actions without exposing UI

- Decision: Set widget intents `openAppWhenRun = true` while keeping host app headless (`.accessory` + no content window scene).
- Why: Ensures the playback engine process starts reliably on tap but does not surface an app window.
- Status: Superseded by 2026-04-20 `openAppWhenRun = false` to preserve widget-only controls and avoid host-process dependency.

## Handoff Visual Integration (2026-04-18)

### Goal

- Adopt the visual language from `/Users/federico.cattaneo/Downloads/handoff/HANDOFF.md` for the existing widget implementation without changing playback architecture.

### Decisions

### 1) Keep runtime architecture, replace presentation only

- Decision: Rework `NTSWidgetExtension/NTSWidget.swift` to match the handoff aesthetics while preserving existing `SharedPlayerState` + App Intent flow.
- Why: User request is specifically visual; changing the state contract or target structure would create unnecessary risk.

### 2) Implement handoff design tokens directly in SwiftUI

- Decision: Add handoff-matched layout spacing, typography, background gradients, button styles, badge styles, and symbol sizing directly in the widget view/components.
- Why: This gives deterministic parity with the supplied reference states while staying native to WidgetKit.

### 3) Add explicit visual-state adapter

- Decision: Introduce a widget-local state adapter (`idle`, `playing`, `paused`, `unavailable`) derived from `SharedPlayerState`.
- Mapping rules:
  - `lastError` present or `statusText == "Unavailable"` -> `unavailable`
  - `isPlaying == true` -> `playing`
  - `currentStation != nil && isPlaying == false` -> `paused`
  - otherwise -> `idle`
- Why: Existing shared state is richer than the handoff’s visual model; adapter ensures fixed labels/badges from the design spec.

### 4) Keep file-level implementation local to avoid project churn

- Decision: Keep the new visual components (`TopRow`, `StatusLine`, `StationButton`, `PlayPauseButton`, `WaveformIcon`) in `NTSWidget.swift` for now.
- Why: Avoids manual `.xcodeproj` edits and keeps scope focused on safe aesthetic integration.

### 5) Expand previews to all required states

- Decision: Ensure previews include `Idle`, `NTS 1 Playing`, `NTS 2 Playing`, `Paused`, and `Unavailable`.
- Why: The handoff defines these five as the visual acceptance set.

## Scope Lock (v1)

- Build a native macOS SwiftUI host app and a WidgetKit extension.
- Keep one widget family only: `systemMedium`.
- Support live playback only for `NTS 1` and `NTS 2`.
- Exclude show metadata, artwork, search, and menu bar UI.
- Keep one fallback host window with the same 3 controls as the widget.

## Architecture Decisions

### 1) Native host app + widget extension

- Decision: Use a standard app target (`NTSWidgetHost`) plus a WidgetKit extension target (`NTSWidgetExtension`) under `macOS 14+`.
- Why: macOS widgets are delivered by an app and extension pairing, and v1 can use the App Intents path without backward branches.

### 2) Shared, app-group-backed playback state

- Decision: Persist one shared model (`SharedPlayerState`) into an app group store.
- State shape: `currentStation`, `isPlaying`, `statusText`, `lastError`, `updatedAt`.
- Why: Widget and app need synchronized, glanceable state with a minimal data contract.

### 3) Playback ownership in app process

- Decision: Keep audio control in `RadioPlayerService` (app target), and have intents route through a shared playback controller locator.
- Why: Widget code should not own AV playback; intents trigger app-owned behavior and then refresh widget timelines.

### 4) Direct stream URLs only

- Decision: Map stations to fixed official live stream URLs:
  - `NTS 1`: `https://stream-relay-geo.ntslive.net/stream`
  - `NTS 2`: `https://stream-relay-geo.ntslive.net/stream2`
- Why: v1 avoids scraping/discovery layers.

### 5) Widget UX constraints

- Decision: Medium utility layout with:
  - top: `NTS` + active station badge
  - middle: one status line
  - bottom: `1`, `2`, and `Play/Pause`
- Why: Keep interactions focused and glanceable.

## Testing Decisions

- Unit test `Station` mapping and stream URL selection.
- Unit test `RadioPlayerService` transitions and failure behavior with engine doubles.
- Unit test intents for station selection and toggle behavior preserving station context.
- Add four widget previews: idle, NTS 1 playing, NTS 2 playing, error.

## Environment Notes

- Command Line Tools are present; full Xcode selection is still required for local build/run of app + widget targets.

## Design Prompt Decisions

### 1) Interpret "cloud design" cautiously

- Decision: Do not treat "cloud design" as a formal widget UI methodology for this project.
- Why: In broader software usage, "cloud design" usually refers to cloud architecture patterns, not desktop widget styling.

### 2) Keep the widget Apple-native first

- Decision: Base the design prompt on macOS WidgetKit behavior and Apple-native utility styling, not on the NTS website look.
- Why: The product brief explicitly optimizes for a real Mac widget that must remain glanceable on the desktop and in Notification Center.

### 3) Use an airy, lightweight visual tone only as a secondary cue

- Decision: If a designer wants a "cloud-like" feeling, express it through softness, calm spacing, rounded geometry, and subtle layered depth rather than literal cloud graphics.
- Why: Literal illustration would fight the v1 scope lock, rendering modes, and legibility requirements.

### 4) Preserve v1 interaction limits in the design brief

- Decision: The design prompt must lock to one `systemMedium` widget, one status line, and exactly three controls.
- Why: Extra controls, metadata, or artwork would push the design away from the agreed v1 scope and the current implementation shape.

### 5) Ask for state-based design output

- Decision: Require designs for idle, NTS 1 playing, NTS 2 playing, paused, and error/unavailable states.
- Why: The widget is state-driven, and the prompt should produce a usable spec rather than a single polished marketing frame.

## Implementation Checkpoints

### Completed scaffold

- Created `macos-nts-widget/NTSWidgetHost.xcodeproj` with three targets:
  - `NTSWidgetHost` (macOS app)
  - `NTSWidgetExtension` (WidgetKit extension)
  - `NTSWidgetHostTests` (unit tests)
- Added shared models and intents under `macos-nts-widget/Shared`.
- Added app playback service (`AVPlayer` wrapper + `RadioPlayerService`) under `macos-nts-widget/NTSWidgetHost`.
- Added one medium widget and timeline/provider state rendering under `macos-nts-widget/NTSWidgetExtension`.
- Added unit tests for station mapping, player transitions, and intent behavior.
- Added a manual validation checklist at `macos-nts-widget/MANUAL_TEST_PLAN.md`.
- Aligned identifiers to:
  - app bundle id: `com.fede.NTSWidgetHost`
  - extension bundle id: `com.fede.NTSWidgetHost.NTSWidgetExtension`
  - app group id: `group.com.fede.NTSWidgetHost`

### Verification status

- `project.pbxproj` passes plist linting.
- `xcodebuild` cannot run in current shell because the active developer directory points to Command Line Tools instead of full Xcode.
- Swift type-check with CLT toolchain is blocked by local toolchain/SDK mismatch in this environment, so compile/test confirmation is pending full Xcode selection.
- Added explicit widget extension `Info.plist` metadata and then reverted the `NSExtensionPrincipalClass` override to stay aligned with default WidgetKit extension loading behavior.
- Updated extension run scheme (`NTSWidgetExtension.xcscheme`) to set `_XCWidgetKind=NTSWidget` so debug launching the extension consistently targets the real widget kind.
- Removed `NSExtensionPrincipalClass` override from widget `Info.plist` to keep WidgetKit extension loading on the template-default path.
- Local-dev registration fix: removed `com.apple.security.application-groups` from host/extension entitlements because current provisioning profile does not advertise app groups, which can block extension registration in widget gallery.
- Added back `com.apple.security.app-sandbox` to the widget extension entitlement set (without app group) to preserve valid macOS extension sandboxing while keeping local registration compatible with current profile.
- Set widget intents `openAppWhenRun = false` to avoid forcing foreground app openings on widget control taps.
- Renamed widget gallery label to `NTS Live (Host)` to reduce confusion with similarly named existing NTS widgets.
