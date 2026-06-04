# LanGuard — design

**Date:** 2026-06-04
**Status:** implemented

## Problem
On a MacBook, when a wired LAN link is active, Wi-Fi should turn off; when no wired link,
Wi-Fi should turn on. Disconnects often happen during sleep, so state must be re-checked on
wake. Originally solved with a shell script + `com.roy.wifitoggle` LaunchAgent; this replaces
it with a native menu-bar app offering per-interface configuration.

## Decisions (locked with user)
- **Stack:** native Swift — SwiftUI `MenuBarExtra` + AppKit, CoreWLAN (Wi-Fi power),
  SystemConfiguration (`SCDynamicStore` link state + change callbacks), SMAppService (login item).
- **Autostart + remove the LaunchAgent:** app does its own monitoring; boots out + deletes
  `com.roy.wifitoggle` on first launch.
- **Override:** respect manual Wi-Fi changes, plus a menu switch to disable auto-toggle entirely.
- **Name:** LanGuard.

## Core logic — edge-based
The engine acts only on wired-link **transitions**:
- wired up → selected Wi-Fi off
- wired down → selected Wi-Fi on

Between edges it never touches Wi-Fi → a manual Wi-Fi change is respected until the next
unplug/replug (this is how "respect override" falls out for free, with no provenance tracking).
Last wired state is persisted, so a transition that happened across sleep registers as an edge
on wake. First launch with wired already up enforces Wi-Fi off once. A master "Auto-toggle"
switch (menu + settings) disables all action.

## Components
| Unit | Responsibility |
|---|---|
| `InterfaceCatalog` | Enumerate + classify Ethernet/Wi-Fi (SystemConfiguration). |
| `NetworkMonitor` | SCDynamicStore notify (link/IPv4) + wake; per-interface link-active read (SC, ifconfig fallback). |
| `WiFiController` | CoreWLAN setPower / powerOn. |
| `ToggleEngine` | Edge state machine; dependencies injected → unit-testable. |
| `AppSettings` | UserDefaults; opt-out sets for wired triggers + controlled Wi-Fi + autoEnabled. |
| `LoginItem` / `LegacyCleanup` | SMAppService login item; remove legacy LaunchAgent. |
| `AppModel` | Wires real implementations into the engine; view-facing helpers. |
| `MenuContent` / `ConfigView` | Menu dropdown + settings window. |

## Config model
Both interface lists are **opt-out**: anything not explicitly disabled is enabled, so a new
wired adapter is auto-counted as a trigger and a new Wi-Fi adapter is auto-controlled. Settings
window shows each interface with a live status dot; changes re-apply immediately (`reapply()`).

## Packaging
Un-sandboxed (CoreWLAN power + launchctl), ad-hoc signed, `LSUIElement=YES` (menu-bar agent,
no Dock icon). macOS 14+. Swift 5 language mode.

## Verification
- 7 unit tests on `ToggleEngine` edge logic (first-run, edge up/down, no-edge override,
  auto-disabled, reapply) — all pass.
- Live: launching with Wi-Fi on + wired up flipped Wi-Fi off; manually re-enabling Wi-Fi while
  docked left it on (override); legacy LaunchAgent removed.

## Notes / deviations
Built directly after design approval at the user's request ("lets go"), so the brainstorming
flow's separate writing-plans/implementation phases were collapsed into this build. This spec is
the as-built record.
