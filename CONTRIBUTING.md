# Contributing to LanGuard

Thanks for your interest in improving LanGuard! Contributions of all kinds are welcome —
bug reports, feature ideas, docs, and code.

## Ground rules

- **`main` is protected.** No direct pushes. All changes land via Pull Request and are
  reviewed/merged by the maintainer ([@roypadina](https://github.com/roypadina)).
- Be respectful — see the [Code of Conduct](CODE_OF_CONDUCT.md).
- Keep changes focused. One logical change per PR.

## Getting started

```bash
git clone https://github.com/roypadina/LanGuard.git
cd LanGuard
# run the unit tests (pure logic — no hardware needed)
cd LanGuardPackage && swift test
# build the app
xcodebuild -workspace LanGuard.xcworkspace -scheme LanGuard -configuration Debug build
```

Requirements: macOS 14+, Xcode 15+ (Swift 5 language mode).

## Architecture

All logic lives in the `LanGuardFeature` Swift package (modular, unit-tested). The app
target (`LanGuard/`) is a thin SwiftUI `MenuBarExtra` shell. See [`CLAUDE.md`](CLAUDE.md)
for a component map.

The core decision logic (`ToggleEngine`, `LoginItem`, `InterfaceCatalog`, `MenuState`) is
written as **pure, dependency-injected functions** so it can be tested without real network
hardware. Please keep new logic testable the same way.

## Workflow

1. **Fork** the repo and create a branch: `git checkout -b feature/my-thing`.
2. Make your change. **Add or update tests** under `LanGuardPackage/Tests/`.
3. Run `swift test` — everything must pass.
4. Follow the existing code style (match surrounding code; no force-unwraps in non-test code).
5. Commit with a clear message and open a **Pull Request** against `main`.
6. CI must be green and the maintainer must approve before merge.

## Commit messages

Short imperative summary line, then a blank line and details if needed. Example:

```
Add failover mode (deprioritize Wi-Fi instead of disabling)

Sets network service order instead of powering Wi-Fi off, for users who
want Wi-Fi to stay available as a fallback.
```

## Feature requests and bugs

- **Feature requests:** [open one](https://github.com/roypadina/LanGuard/issues/new?template=feature_request.yml) and say what you're trying to do; that matters more than the exact feature. Search the [open requests](https://github.com/roypadina/LanGuard/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement) first and 👍 an existing one if it's there.
- **Bugs:** use the [bug report](https://github.com/roypadina/LanGuard/issues/new?template=bug_report.yml). Include your macOS version and the relevant interface names (`networksetup -listallhardwareports`).
- **Ko-fi supporters:** add your Ko-fi name to the request and it goes to the front of my queue. It's a thank-you, not a purchase: no promise on what ships or when.
- **Bigger changes:** open an issue before the PR so we agree on the shape first. Small, focused PRs can come straight in.
- Replies are best effort, evenings and weekends. I read everything.
