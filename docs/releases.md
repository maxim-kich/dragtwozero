# Releases

Planned repository: https://github.com/maxim-kich/dragtwozero
Sole release maintainer: @maxim-kich.

## Current stage

0.0.3 is being prepared locally as **Drag 2.0 (Alpha)** after local T3 Code testing found remaining delivery regressions in 0.0.2. Keep the app in alpha until testing confirms it works reliably; moving to beta requires a separate readiness decision. A local DMG design preview and an explicit Developer ID signing/notarization workflow are available. Packaging does not publish a release or replace the installed app. Native acceptance and clean-machine installation checks remain release gates.

## macOS support policy

Official support focuses only on the latest major macOS release after native validation. Keep the installation minimum at macOS 13 on Apple Silicon: older versions may work, but are unsupported and have no guaranteed compatibility or fixes. Older-version testing is optional and does not block release under this policy. Retain runtime availability guards and fallbacks.

The current candidate was tested on macOS 26.4.1. Apple's [current macOS list](https://support.apple.com/en-us/109033) identifies macOS 27 as the latest major release; validation there remains required before claiming latest-release support. Recheck that list when preparing a release, and name the actual tested versions in its notes. The support policy must not silently turn an untested future major version into a compatibility promise.

## Hosting contract

Use GitHub Releases as the download source. The website and native updater should point to the same release assets, not separately maintained copies.

- Tag: `v0.0.3` (must match VERSION).
- Release title: `Drag 2.0 (Alpha) 0.0.3`.
- Updater asset: `Drag-2.0-v0.0.3-macOS-arm64.zip`; an optional `.dmg` may also be offered for manual installation.
- Attach the generated, signed `appcast.xml` to the same release. See [updater setup](updater.md).
- Attach `SHA256SUMS.txt` and plain-language release notes.
- Versioned link: `https://github.com/maxim-kich/dragtwozero/releases/download/v0.0.3/Drag-2.0-v0.0.3-macOS-arm64.zip`.
- Always-current landing page: `https://github.com/maxim-kich/dragtwozero/releases/latest`.

The versioned URL above is a future example, not an available download. GitHub's automatic source-code archives are not installable app builds. Do not mark a release latest until its actual Apple Silicon ZIP and signed appcast are uploaded and verified.

### Alpha naming and updates

**Drag 2.0 (Alpha)** is the app name. Publish current alpha builds as ordinary GitHub releases, with the **Set as a pre-release** checkbox off. This does not describe the app as stable; its title and release notes should state its alpha status and limitations. The updater discovers newer ordinary releases with a signed ZIP and matching signed appcast.

A separate build that follows only prereleases is future work. The current updater ignores GitHub prereleases, so do not use that checkbox for updates intended for current users. Keep tags numeric, such as `v0.0.1`; keep Alpha in the display name and release title.

Use the [0.0.3 release-note draft](release-notes-0.0.3.md) as the starting point, replacing pending validation with actual results before publication.

## Manual release gate (next phase)

1. Review changes and bump VERSION. Keep versions numeric; never reuse a published tag.
2. Pass CI and the manual checks in testing.md.
3. Build Apple Silicon; sign with Developer ID Application, enable Hardened Runtime and secure timestamp, notarize and staple. A development/ad-hoc signature is not a distribution substitute.
4. Test the actual quarantined package on a clean system. Check icon, name, version, permissions, caret delivery, and updater.
5. Create a draft GitHub Release; attach the verified ZIP, signed appcast, checksum and notes.
6. Publish manually as latest only after review. Connect the website download to that exact asset and verify its checksum/download.
7. Verify the previous app version discovers the new release.

No CI workflow currently publishes releases or has access to signing secrets. The local packaging workflow uses credentials from the maintainer's Keychain.

## Signed and notarized ZIP

Create a Developer ID Application certificate in Xcode and store notarization credentials once in your local Keychain:

```sh
xcrun notarytool store-credentials "drag2-notary"
```

Enter the developer Apple Account, Team ID, and app-specific password at the interactive prompts. Keep credentials out of source files, command arguments, and chat.

Then run:

```sh
swift test
./scripts/package-release.sh
```

The script builds a fresh arm64 app with Developer ID Application signing, Hardened Runtime, and a secure timestamp. It submits a temporary ZIP to Apple, waits for acceptance, saves Apple's log, staples and validates the app's ticket, and checks the signature and Gatekeeper assessment before creating the final ZIP, signed `appcast.xml`, and `SHA256SUMS.txt`. Set `DRAGTWOZERO_NOTARY_PROFILE` to use another Keychain profile or `DRAGTWOZERO_SIGN_IDENTITY` to select a specific certificate.

Each run writes to a new `dist/notarized-vVERSION.XXXXXX/` directory, preserving existing builds and DMG previews. The directory contains the final `Drag-2.0-vVERSION-macOS-arm64.zip`, the stapled app, submission ID, and validation evidence. If the 20-minute notarization wait times out, use the saved ID to check the existing submission with `xcrun notarytool info ID --keychain-profile drag2-notary`; do not submit another copy merely to resume waiting. The ZIP must be rebuilt after stapling. This script does not tag, push, install, or publish anything.

## GitHub settings to apply after creating the remote

### Project description and links

- Repository name: `dragtwozero`, under `maxim-kich`.
- Description: **Drag text and links between Mac apps. A native, open-source utility for Apple Silicon.**
- Website / homepage: **https://dragtwozero.com**.
- Topics: `macos`, `swift`, `appkit`, `productivity`, `drag-and-drop`, `apple-silicon`.
- Source: https://github.com/maxim-kich/dragtwozero.
- Downloads: https://github.com/maxim-kich/dragtwozero/releases.
- Bug reports and proposals: https://github.com/maxim-kich/dragtwozero/issues/new/choose.
- Security policy: https://github.com/maxim-kich/dragtwozero/security/policy.

These GitHub URLs are planned destinations until the repository is published. Set the description and Website field in the repository's **About** settings. Link to the Releases page until a verified app asset is available; do not advertise the example download URL as live.

### Repository configuration

- Public repository, MIT, using the description and homepage above.
- Only @maxim-kich has maintain/admin access; no bots with write access by default.
- Enable Issues. Enable private vulnerability reporting. Discussions are optional; feature proposals can stay in Issues for now.
- Push only the reviewed branch and intended release tags; never use `git push --mirror` or publish local checkpoint refs.
- Default branch main. Allow squash merging; disable merge commits/rebase if a simple linear history is desired. Delete merged branches.
- Protect main against force-push/deletion. Require the CI check “Build and test (Apple Silicon)” once it has run.
- Use PRs for review/history, but do not require a second person's approval or CODEOWNER self-approval: there is only one maintainer. Keep an explicit maintainer bypass for urgent recovery if using a ruleset.
- Restrict creation/update/deletion of release tags to the maintainer; do not overwrite released tags.
- Enable available secret scanning/push protection. Keep workflow token permissions read-only; do not run untrusted PR code with signing secrets or pull_request_target.

These are prepared settings, not claims that remote protection is already configured. A local CODEOWNERS file requests review after publication; it does not enforce permissions by itself.

## Local DMG design preview

After building the app, run `./scripts/build-dmg.sh`. It renders the existing Finder background, packages the app with an Applications shortcut, and verifies the compressed image. Install `uv` first: the script uses pinned `dmgbuild==1.6.7` through `uvx` to write Finder metadata without GUI automation. Output is `dist/Drag-2.0-Alpha-vVERSION-macOS-arm64-preview.dmg`; the script refuses to overwrite an existing image. This preview is not notarized or ready for public distribution.

`package-release.sh` also creates the same styled DMG from the stapled app, signs and notarizes the DMG, staples its ticket, and checks Gatekeeper. The ZIP, DMG and appcast are included in `SHA256SUMS.txt`. DMG submission/result JSON files are saved beside the image; resume their existing submission ID if Apple is still processing. `DRAGTWOZERO_APP_PATH` and `DRAGTWOZERO_DMG_PATH` select explicit input/output paths for standalone packaging; release mode additionally requires `DRAGTWOZERO_RELEASE_SIGNING=1` and an already notarized, stapled input app. All signing credentials stay in Keychain.
