# Drag 2.0 (Alpha) 0.0.2

Maintainer draft. This release is not published. Complete final acceptance, record the results below, and remove this draft notice before using these notes on GitHub. Publish as an ordinary GitHub release; Alpha is the app name.

Drag text and links between Mac apps. Hold a shortcut, pick a block, and drop it into a supported input at its existing caret.

## Regression candidate

This candidate follows fresh-machine reports of unreliable Buffer confirmation, mixed image/text capture, selected-text highlighting, and clipboard restoration. Fixes and native regression validation are in progress; this draft does not claim those reports are resolved. The finalized legal documents are included in this candidate.

## Included

- Text and link dragging with a configurable shortcut, appearance, haptics, and formatting.
- Optional single-item Buffer for carrying content between apps.
- Experimental Multi-select and Drag selected text, off by default.
- Six-step first-launch introduction with Accessibility setup, shortcut selection, optional Buffer, and notification choices.
- In-app updates with signed feeds and archives, optional notifications, and separate download and restart confirmations.

## Requirements and limitations

Apple Silicon Mac. The installation minimum is macOS 13, while official support focuses only on the latest major macOS release after validation. Older versions may work but are unsupported. Liquid Glass requires macOS 26 or later.

This candidate was tested on macOS 26.4.1. macOS 27 validation remains pending; do not describe latest-release support as verified until it passes. Record the final tested app/browser versions before publication.

This is an alpha. Compatibility depends on the source and destination apps' Accessibility support. See the [usage guide](usage.md#compatibility-and-limitations) for current limitations.

## Install

Download the **macOS arm64 ZIP attached to the release**, extract it, and move **Drag 2.0 (Alpha).app** to Applications. Open it and follow the Accessibility setup. GitHub's automatic **Source code** archives are for building the app, not installation.

The release includes `SHA256SUMS.txt`. To verify the ZIP, place both downloads in the same folder and run `shasum -a 256 -c SHA256SUMS.txt --ignore-missing` there. The ZIP must report `OK`; the option skips checks for the optional DMG and appcast when you have not downloaded them.

For future versions, use **Settings → About → Check for Updates → Download & Install → Restart**. Download/preparation and restart require separate confirmations. Finish active transfers and use or clear Buffer before restarting. Builds from before the integrated updater need one manual installation of an updater-enabled version.

## Complete before publication

- Record the final source commit and tested macOS/source/destination versions.
- Record native acceptance, browser compatibility, fresh-permission and clean-install results; state any remaining limitations.
- Verify the final attached ZIP, Developer ID signature, notarization ticket, and checksum.
- Replace the relative usage-guide link above with its URL at the published release tag.
- Review these notes against the final build and remove this section before publication.

[Website](https://dragtwozero.com) · [Legal & Privacy](https://dragtwozero.com/legal#app-privacy)
