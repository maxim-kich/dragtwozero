# Changelog

## 0.0.4 — 2026-10-27

- Add optional Launch at login in onboarding and General; reorganize Settings into Behaviour, Buffer, Appearance and Experimental pages.

- Pick up selected text from a hint under the pointer without requiring source outlines. After grabbing the hint, the shortcut can be released while dragging; releasing it before grabbing cancels.
- Keep bold labels and body text together in generic Accessibility bullet items without merging neighboring items.
- Add selection-hint, cancellation, stale-result, display-edge and list-item regression checks, and update the experimental help.
- Retain the documented browser paste and mixed clickable-image selection limitations. See the [release notes](docs/release-notes-0.0.4.md) for verification scope.

## Initial alpha development — included in 0.0.4

- Initial **Drag 2.0 (Alpha)** app for Apple Silicon Macs, with shortcut-driven text and link dragging.
- Configurable shortcut, appearance, haptics, animations, and content formatting.
- Optional single-item Buffer for carrying content between apps.
- Experimental Multi-select and Drag selected text, both off by default.
- First-launch onboarding with Accessibility permission status, optional launch at login, shortcut setup, optional Buffer, and update-notification choices.
- Clipboard overwrite preference, off by default, with protection for newer clipboard content.
- In-app updates from ordinary GitHub Releases through Sparkle, with signed feeds/archives, optional notifications, and separate download and restart confirmations.
