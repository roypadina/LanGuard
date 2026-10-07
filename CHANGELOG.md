# Changelog

All notable changes to LanGuard are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-10-07

### Added
- **Connection protection** (optional, Settings › Protection): traffic uses a stable address that moves
  between LAN and Wi-Fi, so running connections (e.g. AI agents, downloads) survive plugging or
  unplugging the LAN or a dock. Root helper + guardian installed with one admin prompt; the guardian
  removes everything within seconds if the network looks wrong. IPv4, DHCP networks where LAN and
  Wi-Fi share a router.
- **Panic**: "Restore normal networking" (top of the menu), a Raycast-friendly script, and a terminal
  one-liner in the README.
- **Switch to Wi-Fi** before unplugging: menu item + global shortcut (default ⌃⌥⌘L, recordable in
  Settings), live progress window, "Safe to unplug LAN" popup.
- Per-notification switches: Wi-Fi-off banner, Wi-Fi-back-on banner, progress window, popup.

### Changed
- Plugging in the LAN now waits until it reaches the internet before turning Wi-Fi off; a LAN without
  internet never cuts Wi-Fi.
- Settings is split into tabs (General, Interfaces, Switching, Protection, About).

## [1.0.4] - 2026-10-03

### Changed
- About is now a custom window (nothing clipped); Settings shows a compact About row; Settings captions no longer truncate.

## [1.0.3] - 2026-10-03

### Added
- About section in Settings, "About LanGuard" and "Support on Ko-fi" menu items.

## [1.0.1] - 2026-06-09

### Fixed
- **Spurious toggle notifications on sleep/wake.** A docked Mac drops its wired Ethernet
  link on sleep and regains it on wake (especially USB/Thunderbolt dock NICs); each
  transition looked like a real unplug→replug, so Wi-Fi was toggled and a banner fired on
  every sleep/wake cycle while stationary. `NetworkMonitor` now ignores link changes while
  asleep, waits for the network to settle after wake before evaluating once, and debounces
  callback bursts / brief flaps. `setWiFiPower` is also idempotent — it only toggles
  interfaces whose power actually differs and only notifies when something really changed.

### Added
- **Opt-in debug logging** (Settings → Debug). Writes timestamped events to
  `~/Library/Logs/LanGuard/languard.log` (off by default, rotates at ~1 MB), with
  **Reveal Logs in Finder** / **Clear Logs** buttons — so an issue can be captured and sent.

## [1.0.0] - 2026-06-05

### Added
- **Edge-based Wi-Fi toggling** — turns Wi-Fi off when a wired LAN link goes up and back on
  when it goes down, acting only on plug/unplug transitions so manual changes are respected.
- **Wake-aware** state reconciliation — a transition that happened during sleep is corrected on wake.
- **Per-interface configuration** — choose which wired adapters trigger and which Wi-Fi
  adapters are controlled; new real adapters are auto-included.
- **Virtual-adapter handling** — bridge / VPN / VM adapters (e.g. VMware `vmnet`) are listed
  but off by default (opt-in), so they can't pin Wi-Fi off.
- **Optional notifications** when Wi-Fi is toggled.
- **Configurable menu-bar indicator** — `LAN` / `Wi-Fi` / `Off`, as icon, icon + label, or label.
- **Master pause switch** to disable all automatic toggling.
- **Start at login** via a self-healing `SMAppService` login item that re-registers if the app moves.
- **Homebrew cask** install: `brew install --cask roypadina/tap/languard`.

### Notes
- macOS 14 (Sonoma) or later.
- Ad-hoc signed, not notarized — first launch requires right-click → Open (or clearing quarantine).

[Unreleased]: https://github.com/roypadina/LanGuard/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/roypadina/LanGuard/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/roypadina/LanGuard/releases/tag/v1.0.0
