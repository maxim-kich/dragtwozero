#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; exit 1; }
RELEASE_SIGNING="${DRAGTWOZERO_RELEASE_SIGNING:-0}"
if [ "$RELEASE_SIGNING" = 1 ] && [ "${DRAGTWOZERO_SKIP_SIGNING:-0}" = 1 ]; then
  echo 'Release builds cannot skip signing.' >&2
  exit 1
fi
SIGN_ID="${DRAGTWOZERO_SIGN_IDENTITY:-${DROP_TO_T3_SIGN_IDENTITY:-}}"
if [ "$RELEASE_SIGNING" = 1 ] && [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)
  [ -n "$SIGN_ID" ] || { echo 'A Developer ID Application signing identity is required.' >&2; exit 1; }
fi
BUILD_ARGS=(-c release --arch arm64)
if [ -n "${DRAGTWOZERO_SCRATCH_PATH:-}" ]; then
  BUILD_ARGS+=(--scratch-path "$DRAGTWOZERO_SCRATCH_PATH")
fi
if [ "${DRAGTWOZERO_SKIP_SIGNING:-0}" = 1 ]; then
  BUILD_ARGS+=(-Xlinker -no_adhoc_codesign)
fi
swift build "${BUILD_ARGS[@]}"
APP="${DRAGTWOZERO_APP_PATH:-$PWD/dist/Drag 2.0 (Alpha).app}"
mkdir -p "$APP/Contents/MacOS"
BIN_DIR=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)
cp "$BIN_DIR/DragTwoZero" "$APP/Contents/MacOS/DragTwoZero"
# SPM links Sparkle, but command-line builds do not embed its framework/helpers.
# ditto preserves the versioned framework symlinks and executable permissions.
SPARKLE_ROOT="${DRAGTWOZERO_SCRATCH_PATH:-$PWD/.build}/artifacts/sparkle/Sparkle"
mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Resources/Legal"
rm -f "$APP/Contents/Resources/Legal/privacy.html" "$APP/Contents/Resources/Legal/legal-notice.html"
cp legal/*.html "$APP/Contents/Resources/Legal/"
cp LICENSE "$APP/Contents/Resources/Legal/LICENSE.txt"
cp "$SPARKLE_ROOT/LICENSE" "$APP/Contents/Resources/Legal/Sparkle-LICENSE.txt"
cp assets/Onboarding/Background.mp4 "$APP/Contents/Resources/OnboardingBackground.mp4"
cp assets/AppIcon/light.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/AppIcon/dark.icns "$APP/Contents/Resources/AppIconDark.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DragTwoZero</string>
<key>CFBundlePackageType</key><string>APPL</string>
<!-- Stable identity retained across the DragTwoZero rename for TCC and preferences. -->
<key>CFBundleIdentifier</key><string>com.maximkich.drop-to-t3</string>
<key>CFBundleName</key><string>Drag 2.0 (Alpha)</string>
<key>CFBundleDisplayName</key><string>Drag 2.0 (Alpha)</string>
<key>CFBundleIconFile</key><string>AppIconDark</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 scripts/configure-updater.py "$APP/Contents/Info.plist" "${DRAGTWOZERO_UPDATE_PUBLIC_KEY_FILE:-$PWD/config/sparkle-public-key.txt}"
# A stable development identity keeps TCC permissions associated with rebuilds.
# Contributors without an identity can still build ad-hoc, but may need to re-grant access.
if [ "${DRAGTWOZERO_SKIP_SIGNING:-0}" != 1 ]; then
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)
fi
if [ "$RELEASE_SIGNING" = 1 ]; then
  ./scripts/sign-sparkle.sh "$APP" "$SIGN_ID" release
  codesign --force --sign "$SIGN_ID" --options runtime --timestamp "$APP"
  codesign --verify --deep --strict "$APP"
  SIGN_DETAILS=$(codesign -d --verbose=4 "$APP" 2>&1)
  printf '%s\n' "$SIGN_DETAILS" | /usr/bin/grep -q '^Authority=Developer ID Application:' || { echo 'Release signature must use Developer ID Application.' >&2; exit 1; }
else
  ./scripts/sign-sparkle.sh "$APP" "${SIGN_ID:--}" development
  codesign --force --sign "${SIGN_ID:--}" "$APP"
fi
fi
printf '%s\n' "$APP"
