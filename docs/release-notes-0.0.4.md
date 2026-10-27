# Drag 2.0 (Alpha) 0.0.4 — release candidate

This candidate changes experimental selected-text pickup and keeps bold labels with their complete list item in sources such as T3 Code.

- Select text, hold the shortcut, and grab the hint directly under the pointer. Drag to an input and release the mouse to drop. The shortcut can be released once the hint is grabbed, including while source validation finishes. Releasing it before grabbing cancels; Escape cancels at any time.
- Selected-text pickup reads and revalidates the actual selected characters and range identity without requiring an outline for every selected line. A missing or changed selection is rejected rather than silently replaced with a larger block.
- Capture bold labels, ordinary text and trailing bold words together when a source exposes a bullet item as a generic Accessibility group. Keep adjacent items separate and preserve the existing read budgets.
- Update the selected-text help and usage guide. Both experimental features remain off by default.

The existing saved-caret delivery, clipboard ownership and Buffer recovery rules remain: confirmed insertion consumes the matching Buffer item and restores the previous clipboard when Overwrite clipboard is off. A newer copy wins. Unconfirmed insertion preserves recovery content and can leave captured content on the clipboard; check the destination before retrying.

Known limitations remain. A source must expose readable selected text through Accessibility. Clickable images or avatars exposed as links can still cancel a mixed Multi-select group. A [known Chromium clipboard race](usage.md#known-chromium-paste-issue) can prevent insertion independently of the experimental features; this candidate does not add a browser-specific paste workaround. The reported automatically inferred Settings menu icon on another Mac remains unverified.

Candidate-specific test counts, native scenarios, signing/notarization evidence and checksums are recorded in the package receipt. Clean-machine installation, physical haptics and the hosted updater after publication remain separate manual checks; a passing build or synthetic fixture does not establish every app/browser combination.

Apple Silicon; installation minimum macOS 13. Official support is limited to the latest major macOS release after validation. The package receipt names the versions actually tested; older installable systems may work but are unsupported. See [compatibility and limitations](usage.md#compatibility-and-limitations).

Legal & Privacy resources retain the reviewed local processing, permissions and updater disclosures. This interaction change adds no telemetry, network feature or persistent captured-content storage.

Install the macOS arm64 ZIP or DMG and verify it against `SHA256SUMS.txt`. GitHub's Source code archives are for building the app. This local candidate does not publish, tag or replace the installed app.

[Website](https://dragtwozero.com) · [Legal & Privacy](https://dragtwozero.com/legal#app-privacy)
