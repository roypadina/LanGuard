# LanGuard

macOS menu-bar app. Turns Wi-Fi **off** when a wired LAN link goes up, **on** when it
goes down. Replaces the old shell `com.roy.wifitoggle` LaunchAgent (the app removes it
on first launch).

## Layout
- `LanGuard/` — app target (`LanGuardApp.swift`): `MenuBarExtra` + Settings `Window`, `AppDelegate` starts `AppModel`.
- `LanGuardPackage/Sources/LanGuardFeature/` — all logic (modular, unit-tested):
  - `InterfaceCatalog` — enumerate + classify Ethernet/Wi-Fi via SystemConfiguration. `isVirtual(bsdName:displayName:)` flags bridge/VPN/VM/tunnel adapters (pure, tested).
  - `NetworkMonitor` — `SCDynamicStore` callbacks (link/IPv4) + `NSWorkspace.didWakeNotification`; per-interface link reads (SC `kSCPropNetLinkActive`, ifconfig fallback).
  - `WiFiController` — CoreWLAN `setPower` / `powerOn` (no sudo, no shell).
  - `Notifier` — `UNUserNotificationCenter` wrapper; banners on Wi-Fi toggle (needs OS permission, requested on launch).
  - `ToggleEngine` — **edge-based** decision logic, dependencies injected → testable.
  - `AppSettings` — UserDefaults. Physical wired + Wi-Fi = **opt-out** (`disabledWired`/`disabledWiFi`); virtual wired = **opt-in** (`enabledVirtual`, off by default). `notificationsEnabled`.
  - `LoginItem` / `LegacyCleanup` — SMAppService login item (self-healing, see below); removes legacy LaunchAgent.
  - `AppModel` — wires everything; singleton `AppModel.shared`. `setWiFiPower` posts the toggle notification.
  - `Views` — `MenuContent` (menu), `ConfigView` (settings window; virtual adapters get a "virtual" badge).
- `Config/` — xcconfig + entitlements. **Un-sandboxed** (CoreWLAN power + launchctl), ad-hoc signed, `LSUIElement=YES` (no Dock icon).

## Core behaviour (edge-based)
Acts only on wired-link **transitions**: up → Wi-Fi off, down → Wi-Fi on. Between edges it
never touches Wi-Fi, so a manual Wi-Fi change is respected until the next unplug/replug.
Last wired state is persisted, so a transition across sleep is seen as an edge on wake.
First launch with wired up enforces Wi-Fi off once. Master "Auto-toggle" switch disables
all action. Physical adapters are opt-out (new real adapters auto-included); virtual
adapters (bridge/VPN/VM, e.g. VMware `vmnet`) are opt-in so they can't pin Wi-Fi off.
A banner notification fires whenever Wi-Fi is actually toggled (if enabled + OS-permitted).

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

## Login item (self-healing)
`LoginItem.ensureRegistered()` runs every launch (`AppModel.start`). It registers the
login item for the **current** bundle path, records it in the `registeredBundlePath`
UserDefault, and auto re-registers if the path changes (app moved/rebuilt-into-/Applications)
or the registration is lost (`.notFound`). On a detected move it re-registers and shows an
info alert; if macOS marks the item `.requiresApproval`, it prompts and opens Login Items
settings. Pure decision in `LoginItem.decide(status:storedPath:currentPath:)` (unit-tested).
Just `cp -R` a new build over `/Applications/LanGuard.app` and relaunch — no manual defaults
surgery needed.

## Gotchas
- `lastWired` UserDefault is the edge memory; delete it to force fresh enforcement.
- `registeredBundlePath` UserDefault tracks where the login item is registered from.
