#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(cat VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
app="${DRAGTWOZERO_APP_PATH:-$PWD/dist/Drag 2.0 (Alpha).app}"
release="${DRAGTWOZERO_RELEASE_SIGNING:-0}"
output="${DRAGTWOZERO_DMG_PATH:-$PWD/dist/Drag-2.0-Alpha-v${version}-macOS-arm64-preview.dmg}"
[[ -d "$app" ]] || { echo 'Build the app first, or set DRAGTWOZERO_APP_PATH.' >&2; exit 1; }
[[ ! -e "$output" ]] || { echo "Already exists: $output" >&2; exit 1; }
command -v uvx >/dev/null || { echo 'Install uv to run the pinned dmgbuild packager.' >&2; exit 1; }
profile="${DRAGTWOZERO_NOTARY_PROFILE:-drag2-notary}"
if [ "$release" = 1 ]; then
  codesign --verify --deep --strict "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute "$app"
fi
staging=$(mktemp -d "${TMPDIR:-/tmp}/drag-dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT
swift scripts/render-dmg-background.swift "$staging/installer.tiff"
export DRAGTWOZERO_DMG_APP="$app"
export DRAGTWOZERO_DMG_BACKGROUND="$staging/installer.tiff"
# Direct Finder metadata preserves the existing layout without GUI automation.
uvx --from dmgbuild==1.6.7 dmgbuild -s scripts/dmg-settings.py 'Drag 2.0 (Alpha)' "$output"
hdiutil verify "$output"
if [ "$release" = 1 ]; then
  identity="${DRAGTWOZERO_SIGN_IDENTITY:-}"
  if [ -z "$identity" ]; then
    identity=$(codesign -d --verbose=4 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)
  fi
  [[ "$identity" == 'Developer ID Application:'* ]] || { echo 'Developer ID Application identity required.' >&2; exit 1; }
  codesign --force --sign "$identity" --timestamp "$output"
  xcrun notarytool submit "$output" --keychain-profile "$profile" --no-progress --output-format json > "$output.submission.json"
  submission=$(/usr/bin/plutil -extract id raw -o - "$output.submission.json")
  printf 'DMG notarization submission: %s\n' "$submission"
  if ! xcrun notarytool wait "$submission" --keychain-profile "$profile" --timeout 20m --no-progress --output-format json > "$output.notarization.json"; then
    xcrun notarytool info "$submission" --keychain-profile "$profile" --output-format json > "$output.notarization.json"
  fi
  status=$(/usr/bin/plutil -extract status raw -o - "$output.notarization.json")
  if [ "$status" != Accepted ]; then
    echo "DMG notarization: $status. Resume submission $submission; do not resubmit." >&2
    exit 1
  fi
  xcrun stapler staple "$output"
  xcrun stapler validate "$output"
  codesign --verify --strict "$output"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$output"
  printf '\nSigned, notarized installer: %s\n' "$output"
else
  printf '\nLocal design preview (not notarized): %s\n' "$output"
fi
