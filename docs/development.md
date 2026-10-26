# Development

Use an Apple Silicon Mac and full Xcode 26+ (the macOS 26 SDK is needed to compile the availability-guarded Liquid Glass code). Command Line Tools alone are insufficient. Check the selected installation with `xcodebuild -version`. If needed, select Xcode in **Xcode → Settings → Locations → Command Line Tools**, then complete any first-launch setup in Xcode.

From the repository root:

```sh
swift test
./scripts/build-app.sh
./scripts/verify-build.sh
open 'dist/Drag 2.0 (Alpha).app' --args --settings
```

The runtime deployment target is macOS 13; Liquid Glass requires macOS 26. Older macOS fallback behavior still needs release QA. Intel is not a supported target.

`VERSION` supplies the displayed release version. The package/target/executable remains DragTwoZero; the app bundle and display name are Drag 2.0 (Alpha) during the alpha stage. The historical bundle ID is retained to preserve Accessibility permissions and preferences.

The build script uses your development signing identity, if present. Set `DRAGTWOZERO_SIGN_IDENTITY=-` for ad-hoc local builds. Neither option makes a public notarized release. Do not commit signing keys or credentials.

For distribution, `DRAGTWOZERO_RELEASE_SIGNING=1` selects an available Developer ID Application identity and enables Hardened Runtime and a secure timestamp. Set `DRAGTWOZERO_SIGN_IDENTITY` to select a specific identity. Release mode rejects skipped signing and signatures from other certificate types. See [releases](releases.md) for notarized packaging.

## Layout

- `Sources/DragTwoZero/`: AppKit UI, capture state, accessibility, delivery and update checker.
- `Tests/DragTwoZeroTests/`: deterministic behavior and serialization checks.
- `assets/AppIcon/`: selected editable SVGs, rendered PNGs, and icon sets.
- `legal/`: bundled legal fallback pages and MIT acknowledgements.
- `scripts/`: local build, icon rendering and validation.
- `.local/`: ignored local archive. Not required to build and never published.

Regenerate icon assets with `./scripts/build-icons.sh`. The current bundle uses `AppIconDark` as its Finder icon; About adapts between the bundled light/dark icons. A future Icon Composer asset could extend system-level icon appearances.

## Updates

`UpdateChecker` fetches the public GitHub latest-release API without authentication, at most daily while enabled. About also offers a manual check. Only newer ordinary GitHub releases with numeric `vMAJOR.MINOR.PATCH` tags, an uploaded nonempty Apple Silicon ZIP, and a matching signed appcast qualify. Prereleases, drafts and source-only releases are not offered.

**Alpha** is part of the current app name, not a separate update channel. Publish these builds as ordinary GitHub releases. A future separate prerelease build will need its own prerelease update policy; that work is outside the current release.

An available update appears in About and the menu. macOS notification permission is requested explicitly in onboarding or when enabling update notifications in About; denial still leaves the in-app notice. The flow is **Check for Updates → Download & Install → Restart**. Download/preparation and installation/restart require separate confirmations. Sparkle verifies signed feeds and archives; restart is blocked while capture, transfer, clipboard verification, or Buffer content is pending. See [updater setup and validation limits](updater.md).

No release yet / offline / API rate-limited states are handled without blocking capture. The updater has no usage analytics or persistent installation identifier. Check settings and notification history live in UserDefaults.

Onboarding includes the bundled looping illustration and a final gesture guide. Native UI automation can navigate the onboarding screens; cross-app capture and insertion need separate native acceptance tests.

The six-step onboarding introduces optional Buffer after shortcut selection and before update notifications. Its switch uses the same saved preference as General settings and stays off for fresh preferences; reading or navigating the page never changes that preference.
