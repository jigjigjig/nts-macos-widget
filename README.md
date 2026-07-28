# NTS macOS Widget
<img width="365" height="184" alt="Screenshot 2026-04-28 at 09 38 19" src="https://github.com/user-attachments/assets/e6057e4b-520e-4412-ae25-b2782040d978" />


A simple macOS desktop widget for listening to NTS Radio.

This project gives you quick access to **NTS 1**, **NTS 2**, and **play/pause** directly from your Mac desktop, without needing to keep a full app window open.

## Download (no Xcode needed)

Grab the latest build from **[Releases](https://github.com/jigjigjig/nts-macos-widget/releases)**.

1. Download `NTS-macOS-Widget-*.zip` and unzip it
2. Drag **NTS Radio** into your **Applications** folder
3. Open it once (see Gatekeeper note below)
4. Right-click the desktop → **Edit Widgets** → search for **NTS** → add it
5. Leave **NTS Radio** running in the background while you use the widget (it has no Dock icon)

### Gatekeeper note

This app is not notarized by Apple, so the first open may be blocked.

- Prefer: right-click **NTS Radio** → **Open** → **Open**
- Or: **System Settings → Privacy & Security** → **Open Anyway**

Requires **macOS 14** or later.

## What It Does

- Lets you start NTS 1 or NTS 2 from a macOS widget
- Includes a play/pause control
- Keeps the interface small, focused, and easy to use
- Runs as a lightweight helper app in the background
- Is designed for people who want quick access to NTS while working

## What It Looks Like

The widget is intentionally minimal: two station buttons and one playback button. No clutter, no search, no menus, and no extra screens.

## Who It Is For

This is for NTS listeners who want a fast way to play the live stations from their Mac desktop.

It is especially useful if you keep widgets visible while working and want music controls that stay out of the way.

## Current Status

This is an early public version of the project. It is focused on the core experience: choosing between NTS 1 and NTS 2 and controlling playback from the widget.

## About NTS

NTS is an independent online radio station. You can learn more at [nts.live](https://www.nts.live/).

This project is unofficial and is not affiliated with, endorsed by, or connected to NTS. NTS names, streams, and related branding belong to their respective owners.

## For Developers

The project is built as a native macOS app with a WidgetKit extension.

It currently includes:

- A macOS host app
- A desktop widget
- Playback controls for NTS 1 and NTS 2
- Shared playback state between the app and widget

### Package a GitHub Release

With Xcode installed:

```bash
./scripts/package-release.sh 1.0.1
# creates dist/NTS-macOS-Widget-1.0.1.zip

./scripts/package-release.sh 1.0.1 --publish
# builds the zip and creates/uploads a GitHub release (needs `gh` auth)
```
