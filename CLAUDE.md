# LanGuard

macOS menu-bar app. Turns Wi-Fi **off** when a wired LAN link goes up, **on** when it
goes down. Replaces the old shell `com.roy.wifitoggle` LaunchAgent (the app removes it
on first launch).

## Layout
- `LanGuard/` — app target (`LanGuardApp.swift`): `MenuBarExtra` + Settings `Window`, `AppDelegate` starts `AppModel`.
- `LanGuardPackage/Sources/LanGuardFeature/` — all logic (modular, unit-tested):
  - `InterfaceCatalog` — enumerate + classify Ethernet/Wi-Fi via SystemConfiguration.
  - `NetworkMonitor` — `SCDynamicStore` callbacks (link/IPv4) + `NSWorkspace.didWakeNotification`; per-interface link reads (SC `kSCPropNetLinkActive`, ifconfig fallback).
  - `WiFiController` — CoreWLAN `setPower` / `powerOn` (no sudo, no shell).
  - `ToggleEngine` — **edge-based** decision logic, dependencies injected → testable.
  - `AppSettings` — UserDefaults; opt-out model for both interface lists.
  - `LoginItem` / `LegacyCleanup` — SMAppService login item; removes legacy LaunchAgent.
  - `AppModel` — wires everything; singleton `AppModel.shared`.
  - `Views` — `MenuContent` (menu), `ConfigView` (settings window).
- `Config/` — xcconfig + entitlements. **Un-sandboxed** (CoreWLAN power + launchctl), ad-hoc signed, `LSUIElement=YES` (no Dock icon).

## Core behaviour (edge-based)
Acts only on wired-link **transitions**: up → Wi-Fi off, down → Wi-Fi on. Between edges it
never touches Wi-Fi, so a manual Wi-Fi change is respected until the next unplug/replug.
Last wired state is persisted, so a transition across sleep is seen as an edge on wake.
First launch with wired up enforces Wi-Fi off once. Master "Auto-toggle" switch disables
all action. Interface lists are opt-out → new adapters are auto-included.

## Build / test / run
```bash
# build (XcodeBuildMCP session default = this workspace)
xcodebuild -workspace LanGuard.xcworkspace -scheme LanGuard -configuration Debug build
# unit tests (engine edge logic)
cd LanGuardPackage && swift test
# install
cp -R "$(built .app)" /Applications/LanGuard.app && open /Applications/LanGuard.app
```
Min macOS 14. Swift 5 language mode (avoids Swift 6 strict-concurrency friction).

## Gotchas
- Login item registers the **running bundle's path** — install to `/Applications` before
  relying on autostart. First-run setup is guarded by the `didInitialSetup` UserDefault;
  `defaults delete com.roy.languard didInitialSetup` to re-run it (e.g. after moving the app).
- `lastWired` UserDefault is the edge memory; delete it to force fresh enforcement.
