#!/usr/bin/env bash
# Build a downloadable Release zip for GitHub Releases (unsigned / ad-hoc).
# Usage:
#   ./scripts/package-release.sh              # build dist/NTS-macOS-Widget-<version>.zip
#   ./scripts/package-release.sh 1.0.1        # set version explicitly
#   ./scripts/package-release.sh --publish    # build + create GitHub release from VERSION
#   ./scripts/package-release.sh 1.0.1 --publish

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XB="$DEVELOPER_DIR/usr/bin/xcodebuild"

if [[ ! -x "$XB" ]]; then
  echo "error: Xcode not found at $DEVELOPER_DIR" >&2
  echo "Install Xcode or set DEVELOPER_DIR." >&2
  exit 1
fi

PUBLISH=0
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      if [[ -n "$VERSION" ]]; then
        echo "error: unexpected argument: $arg" >&2
        exit 1
      fi
      VERSION="$arg"
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  VERSION="$(
    "$XB" -project NTSWidgetHost.xcodeproj -scheme NTSWidgetHost -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/MARKETING_VERSION/ { print $2; exit }'
  )"
  VERSION="${VERSION:-1.0.0}"
fi

# Normalize: accept 1.0 or v1.0.0
VERSION="${VERSION#v}"
TAG="v${VERSION}"
PRODUCT_NAME="NTS-macOS-Widget"
ZIP_NAME="${PRODUCT_NAME}-${VERSION}.zip"
DERIVED="$ROOT/build/DerivedData"
DIST="$ROOT/dist"
STAGE="$DIST/stage"
APP_SRC="$DERIVED/Build/Products/Release/NTSWidgetHost.app"
APP_DST="$STAGE/NTS Radio.app"

echo "==> Building universal Release ${TAG}"
rm -rf "$DERIVED"
"$XB" \
  -project NTSWidgetHost.xcodeproj \
  -scheme NTSWidgetHost \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  -allowProvisioningUpdates \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS='arm64 x86_64' \
  build

if [[ ! -d "$APP_SRC" ]]; then
  echo "error: expected app missing: $APP_SRC" >&2
  exit 1
fi

echo "==> Staging and ad-hoc signing for distribution"
rm -rf "$STAGE" "$DIST/$ZIP_NAME"
mkdir -p "$STAGE"

# Friendlier Finder name; bundle id stays com.fede.NTSWidgetHost
ditto "$APP_SRC" "$APP_DST"

HOST_ENTS="$(mktemp -t nts-host-ents).plist"
APEX_ENTS="$(mktemp -t nts-appex-ents).plist"
cleanup() { rm -f "$HOST_ENTS" "$APEX_ENTS"; }
trap cleanup EXIT

codesign -d --entitlements :- "$APP_DST" 2>/dev/null | plutil -convert xml1 -o "$HOST_ENTS" -
APEX="$APP_DST/Contents/PlugIns/NTSWidgetExtension.appex"
codesign -d --entitlements :- "$APEX" 2>/dev/null | plutil -convert xml1 -o "$APEX_ENTS" -
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$HOST_ENTS" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$APEX_ENTS" 2>/dev/null || true

codesign --force --sign - --entitlements "$APEX_ENTS" --timestamp=none "$APEX"
codesign --force --sign - --entitlements "$HOST_ENTS" --timestamp=none "$APP_DST"
codesign --verify --deep "$APP_DST"

cat > "$STAGE/How to install.txt" <<'EOF'
NTS macOS Widget — install

1. Drag "NTS Radio" into your Applications folder.
2. Open it once (you may need to right-click → Open the first time).
3. If macOS says it cannot check for malicious software:
   - Open System Settings → Privacy & Security
   - Scroll to the message about "NTS Radio" and click Open Anyway
   - Confirm Open
4. Add the widget:
   - Right-click the desktop → Edit Widgets
   - Search for "NTS" and add it
5. Keep "NTS Radio" running in the background while you use the widget
   (it has no Dock icon; quit it from Activity Monitor if needed).

This build is not notarized by Apple. That is expected for this free distribution.
Requires macOS 14 or later.
EOF

echo "==> Creating $DIST/$ZIP_NAME"
mkdir -p "$DIST"
rm -f "$DIST/$ZIP_NAME"
# Zip stage *contents* (app + install note), not a wrapping "stage/" folder.
# ditto preserves macOS app-bundle metadata better than zip(1) alone.
(
  cd "$STAGE"
  ditto -c -k --sequesterRsrc --keepParent "NTS Radio.app" "$DIST/$ZIP_NAME"
  zip -q -j "$DIST/$ZIP_NAME" "How to install.txt"
)

# Drop quarantine on the local artifact so you can smoke-test it
xattr -cr "$DIST/$ZIP_NAME" 2>/dev/null || true

echo
echo "Done: $DIST/$ZIP_NAME"
lipo -info "$APP_DST/Contents/MacOS/NTSWidgetHost" || true
ls -lh "$DIST/$ZIP_NAME"

if [[ "$PUBLISH" -eq 1 ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh CLI required for --publish" >&2
    exit 1
  fi
  echo "==> Publishing GitHub release ${TAG}"
  NOTES="$(mktemp -t nts-release-notes)"
  cat > "$NOTES" <<EOF
## NTS macOS Widget ${VERSION}

Desktop widget for NTS 1 / NTS 2 with play/pause.

### Install
1. Download **${ZIP_NAME}** below
2. Unzip, drag **NTS Radio** to Applications
3. Right-click → **Open** the first time (see Gatekeeper note)
4. Desktop → Edit Widgets → add **NTS**

### Gatekeeper
This build is not notarized. On first launch macOS may block it. Use **Privacy & Security → Open Anyway**, or right-click → Open.

### Requirements
- macOS 14+
- Apple Silicon or Intel Mac

Unofficial fan project — not affiliated with NTS.
EOF
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DIST/$ZIP_NAME" --clobber
    echo "Uploaded asset to existing release ${TAG}"
  else
    gh release create "$TAG" "$DIST/$ZIP_NAME" \
      --title "NTS macOS Widget ${VERSION}" \
      --notes-file "$NOTES"
  fi
  rm -f "$NOTES"
  echo "Release URL:"
  gh release view "$TAG" --json url -q .url
fi
