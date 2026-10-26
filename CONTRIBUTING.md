# Contributing

Drag 2.0 has one maintainer: [Maxim Kich](https://github.com/maxim-kich). Review time is limited. A pull request is a proposal, not a commitment to review or merge it.

## Before writing code

- Search existing issues first. Report a reproducible bug using the issue form.
- Small fixes for clear bugs or documentation errors can go directly to a PR.
- New features, behavior/default changes, dependencies, substantial refactors, and new app-specific adapters need an issue with explicit maintainer agreement on scope before implementation.
- Approval of an idea does not guarantee acceptance of its implementation.

## Keep the change focused

Solve one underlying problem per PR. Include the code, tests and documentation needed for that problem; leave unrelated cleanup out. Explain the before/after behavior in plain language. Draft PRs follow the same scope rules.

Preserve content privacy, existing editor carets, clipboard ownership, cancellation, and single-item dragging. Never auto-submit pasted content. Don't add network collection or dependencies without discussing the need first.

## Verify what changed

Use the relevant tests and manual checks in [docs/testing.md](docs/testing.md). Run `swift test` and `./scripts/build-app.sh` before marking a code change ready. Include macOS and app versions for cross-app issues. Visual changes need screenshots; motion or gestures need a short recording. Attach evidence to the PR, not the source tree. State anything you couldn't test.

AI-assisted contributions are welcome. You remain responsible for the code, licensing, and verification. Do not submit generated changes you cannot explain or fabricated test results.

## Review

Use a descriptive title such as `fix: preserve the composer caret on drop`. Respond to review, keep the scope stable, and avoid opening duplicate PRs to bypass a closed proposal. Be respectful; harassment and publication of other people's private information are not acceptable.

Only the maintainer merges changes, sets project direction, and publishes releases. There is no promised review or support response time. Your contributions are made under the project's MIT license.
