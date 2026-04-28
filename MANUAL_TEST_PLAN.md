# Manual Test Plan (macOS)

## Preconditions

- Full Xcode is installed and selected (`xcode-select` points to Xcode).
- App Group identifier is configured in Signing & Capabilities for both app and extension.
- The app and widget extension build successfully on `macOS 14+`.

## Desktop / Notification Center widget checks

1. Add `NTS Live` widget to the desktop.
2. Add `NTS Live` widget to Notification Center.
3. Verify widget layout has:
   - top row `NTS` + station badge
   - middle single status line
   - bottom controls `1`, `2`, `Play/Pause`

## Playback flow checks

1. Start playback from the widget while host app is not already open.
2. Switch `NTS 1` to `NTS 2` while audio is playing.
3. Pause and resume from the widget.
4. Relaunch the app and confirm status sync remains consistent between app window and widget.

## Failure path checks

1. Disable network temporarily.
2. Trigger playback from widget.
3. Confirm widget shows a readable unavailable state.
4. Re-enable network and confirm recovery via widget controls.
