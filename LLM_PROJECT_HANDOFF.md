# NTS Widget Project Handoff (for LLM continuation)
Date: 2026-08-31
Repo root: see the working checkout; see CLAUDE.md for build/verify commands

## 1) Project objective
Build a native macOS widget for live NTS radio with:
- One widget family: `systemMedium`
- Two stations only: `NTS 1` and `NTS 2`
- Controls only: station `1`, station `2`, `Play/Pause`
- No artwork, no metadata feed, no search, no menu bar app surface

## 2) Current state summary
- Visual design is customized to match the external handoff aesthetic.
- Widget interaction uses `ntsradio://` URL links opened through LaunchServices and handled by the host
  (`WidgetActionURLHandler`). App Intents are NOT used: `linkd` refuses the required XPC connection for an
  app with no code-signing identity, and acquiring one needs restricted entitlements that AMFI SIGKILLs
  without a profile (this free team's profiles last 7 days). The intent types remain but are unused.
- Host app is headless (`LSUIElement = YES`, `.accessory`) and does not present a normal window.
- Shared state is persisted as an atomic JSON file inside the widget extension's sandbox container.
- Signing carries NO profile-dependent entitlements and no embedded provisioning profile: the free team's
  profiles expire in 7 days and an expired profile makes AMFI refuse to spawn the app, which renders the
  widget as a blank black rectangle (this broke 1.0.1). The extension keeps `app-sandbox` because macOS
  will not register an unsandboxed extension; the host is unsandboxed so it can write the state file.
- Widget gallery snapshots are intentionally static; timeline reloads read shared state only. Provider code must not fetch network data, write state, create AVPlayer, or run host sync work.

## 3) Architecture
### 3.1 Targets
- `NTSWidgetHost` (macOS app target)
- `NTSWidgetExtension` (WidgetKit extension target)
- `NTSWidgetHostTests` (unit tests)

### 3.2 Core shared contract (Shared/)
- `Station`: station enum + stream URL mapping.
- `SharedPlayerState`: shared state model (`currentStation`, `isPlaying`, `statusText`, `lastError`, `updatedAt`).
- `PlaybackControlling`: protocol for playback actions.
- `SharedPlayerStateFileStore`: file-backed persistence in the extension container.
- `WidgetAction`: encodes/parses the `ntsradio://` control URLs (the live mechanism).
- `PlayStationIntent` + `TogglePlaybackIntent`: legacy App Intents, retained but unused.
- `WidgetReloader`: timeline refresh helper.
- `PlaybackControllerLocator`: runtime-selected playback controller.

### 3.3 Playback implementations
- `RadioPlayerService` (in `NTSWidgetHost/RadioPlayerService.swift`)
- App-process playback service implementing `PlaybackControlling`.
- Owns the durable `AVPlayerEngine`, persists state, fetches metadata after playback starts, and reloads the widget once per meaningful state change.
- Normalizes stale persisted `isPlaying = true` state to paused on host launch so rebuild/cold launch cannot auto-start audio.
- `HostRequiredPlaybackController` (in `Shared/PlaybackControllerLocator.swift`)
- Default inert controller for non-host contexts.
- Does not create `AVPlayer`, write shared state, or reload timelines.
- Exists so accidental extension-side intent execution fails safely instead of trying to stream inside WidgetKit.

### 3.4 Widget UI
- Single medium widget (`NTSWidget`).
- Snapshot provider returns idle immediately for gallery/add stability.
- Timeline provider reads shared state only so the placed widget reflects playback.
- Provider must stay side-effect-free: no network calls, no state writes, no audio work.
- Visual state adapter maps shared state to `idle`, `playing`, `paused`, `unavailable`.
- Layout uses weighted control row (`1 : 1 : 1.25`) and custom gradients/styling.
- Widget config includes:
- `.containerBackgroundRemovable(false)`
- `.contentMarginsDisabled()`

## 4) Runtime flow (current)
### 4.1 Station button (1/2)
1. Widget `Link` opens `ntsradio://play?station=<id>`.
2. LaunchServices launches the hidden host if needed.
3. Host app installs `RadioPlayerService.shared` into `PlaybackControllerLocator`.
4. `WidgetActionURLHandler` executes `RadioPlayerService.play(station:)`.
5. Host-owned `AVPlayerEngine` loads the stream URL and starts playback.
6. Shared state is written to the JSON file in the extension container and the timeline is reloaded.

### 4.2 Play/Pause button
1. Widget `Link` opens `ntsradio://toggle`.
2. LaunchServices launches the hidden host if needed.
3. `WidgetActionURLHandler` executes `RadioPlayerService.togglePlayback()`.
4. Host-owned playback pauses or resumes based on current state.
5. Shared state is persisted and widget timelines are reloaded.

### 4.3 Host app bootstrap path
- In host app init:
- `PlaybackControllerLocator.controller = RadioPlayerService.shared`
- app activation policy set to `.accessory`
- The host does not run external state sync on launch.
- Because the controls are URL links, widget taps start a durable hidden playback process without exposing a Dock/Cmd-Tab app.

## 5) Major implementation timeline
### 2026-04-18
- Initial scaffold created:
- project, targets, shared models, intents, service, tests, basic widget.

### 2026-04-19 (visual/runtime parity phase)
- Fixed desktop-installed widget visual mismatch:
- locked container background, disabled auto margins.
- Added deterministic control sizing.
- Improved dark-mode control contrast.
- Made host app headless to avoid visible UI launch from widget interactions.

### 2026-04-19 to 2026-04-20 (state/playback routing experiments)
- Added explicit app-group entitlements for app + extension.
- Migrated shared state to app-group JSON file with legacy plist migration.
- Added distributed notification signaling for host-sync model.
- Tried host-owned playback path (`openAppWhenRun = true`, state-only intents, host reacts to state).

### 2026-04-20 (stream regression fix)
- Observed regression: widget state changed but no audio because host process was not reliably alive.
- Reverted intents to direct playback execution via controller.
- Set `openAppWhenRun = false` again.
- Removed suite `UserDefaults` use in app-group mode to avoid CFPrefs warnings in extension hot path.

## 6) Key files to inspect first
- `NTSWidgetExtension/NTSWidget.swift`
- `Shared/WidgetAction.swift`
- `NTSWidgetHost/Info.plist` (declares the `ntsradio` scheme)
- `Shared/PlaybackControllerLocator.swift`
- `Shared/SharedPlayerStateStore.swift`
- `NTSWidgetHost/NTSWidgetHostApp.swift`
- `NTSWidgetHost/RadioPlayerService.swift`
- `NTSWidgetHost/AVPlayerEngine.swift`
- `NTS_WIDGET_WORKFLOW.md`
- `MANUAL_TEST_PLAN.md`

## 7) Entitlements and identifiers
- App bundle id: `com.fede.NTSWidgetHost`
- Extension bundle id: `com.fede.NTSWidgetHost.NTSWidgetExtension`
- Host entitlements: **empty** (unsandboxed, ad-hoc signed).
- Extension entitlements: `com.apple.security.app-sandbox = true` and nothing else.
- No `application-identifier`, `team-identifier`, `keychain-access-groups`, `application-groups`, or
  embedded provisioning profile anywhere. `scripts/package-release.sh` enforces this.

## 8) Known operational pitfalls
- Desktop widget can run stale code from `/Applications/NTSWidgetHost.app` instead of latest DerivedData output.
- Rebuilding in Xcode is not always enough to update installed widget behavior.
- Notification Center / widget extension process caching can hide new behavior until processes are restarted.
- Do not add network requests, shared-state writes, AVPlayer ownership, or infinite animations to `NTSWidgetProvider` or widget rendering paths. Those can stall the widget gallery/sidebar.
- Replacing `/Applications/NTS Radio.app` deregisters the widget extension. Re-run
  `lsregister -f -R "/Applications/NTS Radio.app"` and confirm with `pluginkit -m -i ...`, or the widget
  stays blank.
- `log show` did not persist this app's `Logger` output on macOS 26.6.2, returning zero lines for a running
  process. Absence of log output proves nothing; use `log stream --level debug` while reproducing.
- Do not "restore" App Intents for the widget controls. It cannot work under this signing setup — see the
  2026-08-31 entry in `NTS_WIDGET_WORKFLOW.md`.

## 9) Build/deploy/debug commands used
- Build extension + host:
- `xcodebuild -project macos-nts-widget/NTSWidgetHost.xcodeproj -scheme NTSWidgetExtension -configuration Debug build`
- Deploy built app to `/Applications` (important for installed widget runtime):
- `ditto /Users/federico.cattaneo/Library/Developer/Xcode/DerivedData/NTSWidgetHost-dmjnyzldswnlslgsvxuowteuhlmg/Build/Products/Debug/NTSWidgetHost.app /Applications/NTSWidgetHost.app`
- Restart runtime processes:
- `killall NTSWidgetExtension NTSWidgetHost NotificationCenter`
- Verify running processes:
- `ps aux | rg -i 'NTSWidgetHost|NTSWidgetExtension|NotificationCenter'`
- Check logs:
- `/usr/bin/log show --last 20m --predicate 'process == "NTSWidgetExtension" OR process == "NTSWidgetHost" OR subsystem CONTAINS "NTS"' --style compact`

## 10) Testing status
- Unit test files exist for station mapping, intents, and service transitions.
- `NTSWidgetHost` scheme currently has no concrete test configuration in CLI test action.
- Building test target via CLI requires `ENABLE_TESTABILITY=YES` when invoked directly.
- Practical verification has been mostly manual via widget install + runtime logging.

## 11) Recommended next steps for next LLM
1. Fix scheme test action so `xcodebuild test` works predictably from CLI.
2. Add one deterministic integration test harness for widget intent -> host playback -> persisted state transitions.
3. Add explicit runtime self-diagnostics (structured logs around intent execution, stream load/play success/failure, and state persistence path).
4. Keep WidgetKit provider/render paths side-effect-free.

## 12) Source-of-truth docs
- `NTS_WIDGET_WORKFLOW.md` contains historical decision log, including superseded decisions.
- `MANUAL_TEST_PLAN.md` contains manual validation checklist.
- This handoff file should be updated after each architecture change.
