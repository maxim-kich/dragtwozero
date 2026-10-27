# Drag 2.0 (Alpha) 0.0.3 — release draft

This candidate addresses false-negative drop confirmation in T3 Code and inconsistent source identity during block selection.

- Confirm complete owned paragraphs at the original selection markers, including empty-input placeholders, saved carets across paragraphs and real blank lines that AXValue omits.
- Verify supported Markdown styling against the editor's actual text attributes when a plain input renders formatted content.
- Refresh destination detection while a drag is stationary, so a late browser hit-test result can recover before release.
- Clear the matching Buffer item and restore the previous clipboard after confirmed insertion when Overwrite clipboard is off. A newer copy still wins; rejected or unconfirmed drops retain recovery content.
- After a restart or a rewritten clipboard revision, preserve the current visible clipboard and its formats when an old temporary owner is gone; discard only stale app metadata.
- Keep the canonical text block as its source anchor, so equal-sized nested Accessibility elements do not cause an unchanged block to be rejected.
- Include the finalized Legal & Privacy notice.

Candidate-specific automated and native results are recorded in the accompanying package receipt. Native checks use complete destination text as the insertion oracle, measure clipboard restoration before copying that text, and explicitly reopen Buffer to check consumption or recovery. Native testing does not establish acceptance on another Mac or validate the hosted updater. Retest the packaged build on a clean machine, and verify the public feed and upgrade path after publication.

Apple Silicon; installation minimum macOS 13. Official support remains limited to the latest major macOS release after validation. Older versions may work but are unsupported. See the [usage guide](usage.md#compatibility-and-limitations) for compatibility limits.

Unknown or transformed editor content that cannot be proved remains unconfirmed. The Buffer item and temporary clipboard payload can remain available for recovery even with Overwrite clipboard off. Check the destination before retrying; there is no automatic retry.

Experimental browser selection limitations remain unresolved. With Drag selected text enabled, an unreadable non-text object/control selection can block ordinary highlighting and Multi-select. Clickable images or avatars exposed as links can also cancel a mixed group when dragging starts. These selection failures can occur wherever a source exposes the same Accessibility state. See the [experimental feature notes and workarounds](usage.md#experimental-features). Both experiments remain off by default; this candidate does not change their capture logic.

Install the release's macOS arm64 ZIP or DMG and verify it against `SHA256SUMS.txt`. GitHub's Source code archives are for building the app. Publishing, hosted-updater acceptance and clean-machine acceptance remain separate release gates.

[Website](https://dragtwozero.com) · [Legal & Privacy](https://dragtwozero.com/legal#app-privacy)
