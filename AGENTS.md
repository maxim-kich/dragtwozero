# Working in Drag 2.0

Read CONTRIBUTING.md before editing. This is an Apple Silicon AppKit utility with one maintainer, @maxim-kich.

- Keep changes focused; preserve user work. Do not publish, push, tag, or upload a release unless asked.
- User-facing app name: Drag 2.0 (Alpha). Public brand: Drag 2.0. Swift target/executable: DragTwoZero. VERSION is the marketing version source of truth.
- Retain the existing bundle identifier and preference keys for permission compatibility.
- Never auto-submit content, replace an unrelated selection, or overwrite a newer clipboard revision.
- Never log captured text, URLs, clipboard payloads, or screenshots. Update checks are the only app-owned network feature; no telemetry without a separate approved design.
- Accessibility/input probing must not block rendering or the event tap. Preserve stale-result rejection and cancellation.
- Use native controls and semantic colors. Keep the gesture's easing when addressing detection delays.
- Build with Xcode 26+; run swift test and scripts/build-app.sh for code changes. Add focused behavior tests, not snapshots of implementation.
- Native interactions still need manual checks. Say what was actually tested; do not equate a successful build with working cross-app gestures.
- .local/, handoff/, dist/, recordings and design experiments are not publishable source. Never bulk-stage the project.
- Keep checklist statuses current and mark completed work before the final response.

## Signing and release builds

- Local development: `./scripts/build-app.sh` uses development/ad-hoc signing. This alone does not produce a notarized release.
- When preparing a signed release package, run `swift test && ./scripts/package-release.sh`. This builds with Developer ID Application, Hardened Runtime, and a secure timestamp; submits to Apple; staples and validates the ticket; checks Gatekeeper; and creates the final ZIP plus checksum in a fresh `dist/notarized-vVERSION.XXXXXX/` directory.
- Notarization credentials are already configured on this Mac in Keychain profile `drag2-notary`. Reuse that profile; verify certificate/profile availability before release work. Never read out, log, or request passwords in chat.
- Read `docs/releases.md` for the complete workflow. If notarization is still processing, use the saved submission ID to resume checking it rather than submitting a duplicate.
- Update `VERSION` for a new published release. Signing/notarization does not replace native gesture, fresh-permission, or clean-machine installation checks. Publishing, uploading to GitHub, tagging, and replacing the installed app require an explicit request.
