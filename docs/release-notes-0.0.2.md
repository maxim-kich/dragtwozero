# Drag 2.0 (Alpha) 0.0.2

Maintainer draft. This release is not published. Complete final acceptance, record the results below, and remove this draft notice before using these notes on GitHub. Publish as an ordinary GitHub release; Alpha is the app name.

Drag text and links between Mac apps. Hold a shortcut, pick a block, and drop it into a supported input at its existing caret.

## Regression candidate

This candidate follows fresh-machine reports of unreliable Buffer confirmation, mixed image/text capture, selected-text highlighting, and clipboard restoration. It includes these fixes and the finalized legal documents:

- Skip images in mixed marquee selections while preserving surrounding supported text and links.
- Confirm complete insertion using the original editor's full accessible text when its value is stale, and recognize browser CRLF-to-LF conversion. Confirmed transfers consume the matching Buffer item and restore the original clipboard when Overwrite clipboard is off.
- Resolve selected-text highlights across inline nodes through exact opaque text markers and visual lines. Large selections receive a bounded background budget; stale or unreadable selections still reject safely.
- Preserve explicit browser bold attributes even when the provider omits a font name. If selected-range metadata omits a link URL, keep its words without inventing a destination.
- Distinguish verification deadlines from cancellation in content-free diagnostic logs.

The final clean-source suite passes 359 tests with zero failures and zero skips, including the real browser selection fixture. Native regression checks on macOS 26.4.1 include mixed image/text marquee, styled wrapped and 14,000-character selections, saved-caret insertion, explicit Buffer reopening, clipboard formats and newer-copy protection. Real Gmail checks cover plain text, multilingual combining characters, multiline text, links, and known emoji images, including the measured two-line-break case. These checks do not establish acceptance on the user's macOS 26.6.2 machine; that packaged-build retest remains required.

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

Local tests using installed Chrome 156.0.8078.48 show intermittent Paste events without insertion. Its versioned source still contains the clipboard-token logic addressed by [Chromium's upstream fix](https://github.com/chromium/chromium/commit/fc5529f522a28df6ff5d5f7e572debc71d6f18e4); this supports the suspected cause but is not a patched-browser comparison. Do not describe Chrome delivery as reliable or this candidate as distribution-ready until that compatibility gate is resolved.

Rich editors can transform emoji into image attachments and expose incomplete text. Unknown attachments or ambiguous line boundaries remain unconfirmed. Buffer retains the item for recovery, and captured content can remain on the clipboard even with Overwrite clipboard off. Check the destination before retrying; there is no automatic retry.

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
