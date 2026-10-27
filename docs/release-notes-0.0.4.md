# Drag 2.0 (Alpha) 0.0.4

Drag 2.0 is a native, open-source utility for dragging text and links between Mac apps. This is an **alpha release** for Apple Silicon.

## Install

Download **Drag-2.0-Alpha-v0.0.4-macOS-arm64.dmg**, open it, drag the app to Applications, then open Drag 2.0 and grant Accessibility access. Launch at login is optional.

The ZIP contains the same signed and notarized app and is also used by the in-app updater. GitHub’s Source code archives are for building from source. Checksums are in `SHA256SUMS.txt`.

## Included in 0.0.4

- Hold Option + Command, pick a text block or link, and drag it to a supported input at its existing caret.
- Optional single-item Buffer, with confirmed delivery consuming the parked item. Clipboard restoration preserves newer copies.
- Experimental Multi-select and selected-text pickup, both off by default. For selected text, select normally, hold the shortcut, grab the hint under the pointer, and drag. You can release the shortcut after grabbing.
- More complete capture of bold labels at the edges of generic list items, including supported T3 Code content.
- Optional Launch at login in onboarding and General settings, with a Login Items handoff when macOS requires approval.
- Settings organized into General, Behaviour, Buffer, Appearance, Experimental and About.
- Signed in-app updates, with confirmation before downloading/installing and restarting. No usage analytics.

## Compatibility and known limitations

Apple Silicon only; installation minimum **macOS 13**. This build was tested locally on **macOS 26.4.1**. Other OS versions and app/browser combinations are not guaranteed. Latest-major macOS validation and an actual logout/login startup check remain pending.

- A known Chromium clipboard race can prevent insertion in some browser states. Unconfirmed drops retain recovery content; check the destination before retrying.
- Clickable images or avatars exposed as links can cancel a mixed Multi-select group.
- Selected-text pickup requires a readable, unchanged Accessibility selection. Some web content and editor/focus states are unsupported.
- macOS can display an automatic gear beside Settings despite the app’s text-only menu preference.

See [usage and limitations](https://github.com/maxim-kich/dragtwozero/blob/v0.0.4/docs/usage.md).

## Validation

400 automated tests passed locally, including three browser integration checks, plus 15 native input-driver delivery scenarios. The browser delivery fixture used Chrome 156 with renderer Accessibility enabled. The app and DMG are Developer ID signed, notarized and stapled. These checks do not establish universal compatibility. The hosted updater will be checked after publication; a real two-version upgrade remains separate validation.

Built from commit `fc6eedda58a640aa86012a0825e4b24a8a376273`. Source and app are MIT licensed; bundled third-party notices are included.

[Website](https://dragtwozero.com) · [Legal & Privacy](https://dragtwozero.com/legal#app-privacy) · [Report a bug](https://github.com/maxim-kich/dragtwozero/issues/new/choose)
