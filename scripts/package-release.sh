#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
PROFILE="${DRAGTWOZERO_NOTARY_PROFILE:-drag2-notary}"
mkdir -p dist
# Each run gets its own directory; existing app bundles and previews are preserved.
OUTPUT_DIR=$(mktemp -d "$PWD/dist/notarized-v${VERSION}.XXXXXX")
APP="$OUTPUT_DIR/Drag 2.0 (Alpha).app"
export DRAGTWOZERO_APP_PATH="$APP"
export DRAGTWOZERO_RELEASE_SIGNING=1
./scripts/build-app.sh
./scripts/verify-build.sh
# Fail before contacting Apple if the release archive/feed cannot be signed.
SPARKLE_ROOT="${DRAGTWOZERO_SCRATCH_PATH:-$PWD/.build}/artifacts/sparkle/Sparkle"
ACCOUNT="${DRAGTWOZERO_SPARKLE_ACCOUNT:-com.maximkich.dragtwozero.updates}"
test "$("$SPARKLE_ROOT/bin/generate_keys" --account "$ACCOUNT" -p)" = "$(cat "${DRAGTWOZERO_UPDATE_PUBLIC_KEY_FILE:-$PWD/config/sparkle-public-key.txt}")" || {
  echo 'Sparkle Keychain signing key must match the embedded public key.' >&2; exit 1;
}

# Notarize the app before creating the final ZIP so it includes the stapled ticket.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT_DIR/notarization-upload.zip"
xcrun notarytool submit "$OUTPUT_DIR/notarization-upload.zip" \
  --keychain-profile "$PROFILE" --no-progress --output-format json > "$OUTPUT_DIR/submission.json"
SUBMISSION_ID=$(/usr/bin/plutil -extract id raw -o - "$OUTPUT_DIR/submission.json")
printf 'Notarization submission: %s\nEvidence: %s\n' "$SUBMISSION_ID" "$OUTPUT_DIR"
if ! xcrun notarytool wait "$SUBMISSION_ID" --keychain-profile "$PROFILE" \
  --timeout 20m --no-progress --output-format json > "$OUTPUT_DIR/notarization-result.json"; then
  xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "$PROFILE" \
    --output-format json > "$OUTPUT_DIR/notarization-result.json"
fi
STATUS=$(/usr/bin/plutil -extract status raw -o - "$OUTPUT_DIR/notarization-result.json")
if [ "$STATUS" != Accepted ]; then
  if [ "$STATUS" = Invalid ] || [ "$STATUS" = Rejected ]; then
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" "$OUTPUT_DIR/notarization-log.json"
  fi
  echo "Notarization status: $STATUS. Submission $SUBMISSION_ID and evidence are saved in $OUTPUT_DIR; do not resubmit to resume waiting." >&2
  exit 1
fi
xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" "$OUTPUT_DIR/notarization-log.json"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
./scripts/verify-build.sh
spctl --assess --type execute --verbose=4 "$APP"
codesign -d --verbose=4 "$APP" 2> "$OUTPUT_DIR/signature.txt"

ARCHIVE="Drag-2.0-v${VERSION}-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT_DIR/$ARCHIVE"
./scripts/generate-update-feed.sh "$OUTPUT_DIR/$ARCHIVE" "$OUTPUT_DIR/appcast.xml"
DMG="Drag-2.0-Alpha-v${VERSION}-macOS-arm64.dmg"
DRAGTWOZERO_DMG_PATH="$OUTPUT_DIR/$DMG" ./scripts/build-dmg.sh
(cd "$OUTPUT_DIR" && shasum -a 256 "$ARCHIVE" "$DMG" appcast.xml > SHA256SUMS.txt)
printf '\nNotarized package: %s/%s\n' "$OUTPUT_DIR" "$ARCHIVE"
printf 'Native interaction and clean-machine installation checks remain required before publishing.\n'
