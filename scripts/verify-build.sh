#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${DRAGTWOZERO_APP_PATH:-$PWD/dist/Drag 2.0 (Alpha).app}"
VERSION=$(cat VERSION)
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleDisplayName' "$APP/Contents/Info.plist")" = 'Drag 2.0 (Alpha)'
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleName' "$APP/Contents/Info.plist")" = 'Drag 2.0 (Alpha)'
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" = 'com.maximkich.drop-to-t3'
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Contents/Info.plist")" = 'DragTwoZero'
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundlePackageType' "$APP/Contents/Info.plist")" = APPL
test "$(lipo -archs "$APP/Contents/MacOS/DragTwoZero")" = arm64
cmp assets/Onboarding/Background.mp4 "$APP/Contents/Resources/OnboardingBackground.mp4"
test -s "$APP/Contents/Resources/AppIcon.icns"
test -s "$APP/Contents/Resources/AppIconDark.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' "$APP/Contents/Info.plist")" = AppIconDark
cmp assets/AppIcon/dark.icns "$APP/Contents/Resources/AppIconDark.icns"
for page in legal/*.html; do
  cmp "$page" "$APP/Contents/Resources/Legal/$(basename "$page")"
done
cmp LICENSE "$APP/Contents/Resources/Legal/LICENSE.txt"
python3 scripts/verify-updater.py "$APP" "${DRAGTWOZERO_UPDATE_PUBLIC_KEY_FILE:-$PWD/config/sparkle-public-key.txt}"
codesign --verify --deep --strict "$APP"
printf 'Verified Drag 2.0 (Alpha) %s, arm64, icons, legal resources, Sparkle and signatures.\n' "$VERSION"
