# LanGuard

macOS menu-bar app. Turns Wi-Fi **off** when a wired LAN link goes up, **on** when it
goes down. Replaces the old shell `com.roy.wifitoggle` LaunchAgent (the app removes it
on first launch).

## Layout
- `LanGuard/` — app target (`LanGuardApp.swift`): `MenuBarExtra` + Settings `Window`, `AppDelegate` starts `AppModel`.
- `LanGuardPackage/Sources/LanGuardFeature/` — all logic (modular, unit-tested):
  - `InterfaceCatalog` — enumerate + classify Ethernet/Wi-Fi via SystemConfiguration. `isVirtual(bsdName:displayName:)` flags bridge/VPN/VM/tunnel adapters (pure, tested).
  - `NetworkMonitor` — `SCDynamicStore` callbacks (link/IPv4) + `NSWorkspace` sleep/wake; per-interface link reads (SC `kSCPropNetLinkActive`, ifconfig fallback). **Flap guard:** ignores link changes while asleep (`willSleepNotification` → `suspended`), waits a settle interval after `didWakeNotification` before evaluating once, and debounces callback bursts/brief flaps (1.5s). Stops a docked Mac's Ethernet dropping on sleep + returning on wake from looking like a real unplug→replug.
  - `WiFiController` — CoreWLAN `setPower` / `powerOn` (no sudo, no shell).
  - `Notifier` — `UNUserNotificationCenter` wrapper; banners on Wi-Fi toggle (needs OS permission, requested on launch).
  - `Log` — opt-in file logger. When `debugLoggingEnabled` (Settings → Debug) is on, appends timestamped events to `~/Library/Logs/LanGuard/languard.log` (rotates at ~1MB, one backup). `Log.write` is a no-op while off. `revealInFinder()` / `clear()` back the Settings buttons. Instrumented across start / evaluate / edges / setWiFiPower / sleep-wake so users can capture + send a log.
  - `MenuIcon` — `MenuState` (lan/wifi/paused, pure mapping) + `MenuIconStyle` (icon / icon+label / label) + `MenuBarLabel` view used as the MenuBarExtra label.
  - `ToggleEngine` — **edge-based** decision logic, dependencies injected → testable.
  - `Handover` — make-before-break moves. `toLAN`: wait until the LAN reaches the internet (`Probe`, TCP to 1.1.1.1:443 scoped by `requiredInterfaceType`), `protection.settle()` with preferWiFi=false, then Wi-Fi off (kept on if protection could not leave Wi-Fi). `toWiFi` (menu + global `HotKey`, recordable `HotKeyCombo`): Wi-Fi on → reachable → `protection.settle()` with preferWiFi=true → "safe to unplug" popup. Floating `ProgressPanel` while it runs.
  - `Protection` — **connection protection**: a stable per-network /32 address A on whichever link is active + routes `0.0.0.0/1`,`128.0.0.0/1 -ifa A`, so TCP connections survive LAN↔Wi-Fi (TCP is pinned to its source IP; A moves, the IP doesn't change). Own undebounced SCDynamicStore watcher + 5 s common-mode timer; serial queue; settings captured as a main-thread `Snapshot`. Only on networks (router IP@MAC) where LAN+Wi-Fi shared a router (learned) or ticked by hand; user "off" → `disabledNetworks`, never re-learned. 30-min hold only when the guardian tore down as `unhealthy`; 5-min hold on verify failure / no free address.
  - `NetHelper` — root side: `Resources/languard-net.sh` → `/Library/PrivilegedHelperTools/languard-net` (verbs up/move/adopt/down/panic/arm/check/status; exit codes mirrored in `NetHelper.Exit`), LaunchDaemon `com.roypadina.languard-net` (`check` every 3 s, ThrottleInterval 1, stamps `/var/run/languard-net.tick`), sudoers `/etc/sudoers.d/languard` = that helper path only. One admin prompt (`install`/`remove`). App never arms without a fresh tick. Panic: menu → helper `panic` → admin fallback → inline `panicOneLiner` (also README + `~/Raycast-Scripts/languard-panic.sh`). Safety contract in the script header; reviewed by 3 Fable gates (2026-10-06).
  - `AppSettings` — UserDefaults. Physical wired + Wi-Fi = **opt-out** (`disabledWired`/`disabledWiFi`); virtual wired = **opt-in** (`enabledVirtual`, off by default). `notificationsEnabled` (Wi-Fi back on), `notifyMovedToLAN`, `switchProgressPopup`, `safeToUnplugPopup`, `hotKey`, `menuIconStyle`, `protectionEnabled`, `protectedNetworks`/`disabledNetworks`, per-network stable address + holds (UserDefaults dicts).
  - `LoginItem` / `LegacyCleanup` — SMAppService login item (self-healing, see below); removes legacy LaunchAgent.
  - `AppModel` — wires everything; singleton `AppModel.shared`. `setWiFiPower` is idempotent — only toggles interfaces whose power actually differs and only posts the banner when something really changed.
  - `Views` — `MenuContent` (menu), `ConfigView` (settings window; virtual adapters get a "virtual" badge).
- `Config/` — xcconfig + entitlements. **Un-sandboxed** (CoreWLAN power + launchctl), ad-hoc signed, `LSUIElement=YES` (no Dock icon).

## Core behaviour (edge-based)
Acts only on wired-link **transitions**: up → Wi-Fi off, down → Wi-Fi on. Between edges it
never touches Wi-Fi, so a manual Wi-Fi change is respected until the next unplug/replug.
Last wired state is persisted, so a transition across sleep is seen as an edge on wake.
First launch with wired up enforces Wi-Fi off once. Master "Auto-toggle" switch disables
all action. Physical adapters are opt-out (new real adapters auto-included); virtual
adapters (bridge/VPN/VM, e.g. VMware `vmnet`) are opt-in so they can't pin Wi-Fi off.
Why protection: a TCP connection is pinned to its source IP; unplugging kills everything opened
over the LAN (live test 2026-10-06: Claude Code stream hung 69 s → "Connection lost mid-response").
Service order / draining can't fix that (pooled keep-alive sockets stay on the LAN). Moving a stable
address between links can (validated: download + Tailscale + Pritunl survived a physical unplug).
A LAN without internet never turns Wi-Fi off. Banners and popups each have a Settings flag.

## Build / test / run
```bash
# build (XcodeBuildMCP session default = this workspace)
xcodebuild -workspace LanGuard.xcworkspace -scheme LanGuard -configuration Debug build
# unit tests (engine edge logic)
cd LanGuardPackage && swift test
# install
rm -rf /Applications/LanGuard.app && ditto "$(built .app)" /Applications/LanGuard.app   # replace, never merge: ditto over an old .app leaves stale files → "sealed resource is missing"; not cp -R (nests)
```
Min macOS 14. Swift 5 language mode (avoids Swift 6 strict-concurrency friction).

## Login item (self-healing)
`LoginItem.ensureRegistered()` runs every launch (`AppModel.start`). It registers the
login item for the **current** bundle path, records it in the `registeredBundlePath`
UserDefault, and auto re-registers if the path changes (app moved/rebuilt-into-/Applications)
or the registration is lost (`.notFound`). On a detected move it re-registers and shows an
info alert; if macOS marks the item `.requiresApproval`, it prompts and opens Login Items
settings. Pure decision in `LoginItem.decide(status:storedPath:currentPath:)` (unit-tested).
Just `ditto` a new build over `/Applications/LanGuard.app` and relaunch — no manual defaults
surgery needed.

## Gotchas
- `lastWired` UserDefault is the edge memory; delete it to force fresh enforcement.
- `registeredBundlePath` UserDefault tracks where the login item is registered from.
- Helper self-test (no root): `bash LanGuardPackage/Tests/helper/selftest.sh`; `shellcheck -s bash` the script.
- `route -n get -net 0.0.0.0/1` falls back to the DEFAULT route when the /1 is absent → `route_if` must require `mask: 128.0.0.0`; never `route change` a /1 (edits the default route) — delete + add.
- Default shortcut is ⌃⌥⌘L, not ⌃⌥⌘W: cmux binds `cmd+ctrl+w` = closeWindow, so missing ⌥ on ⌃⌥⌘W closes the whole cmux window.
- "Who toggled Wi-Fi?": `/usr/bin/log show --last 30m --predicate 'process == "airportd" AND eventMessage CONTAINS "SET POWER"'` prints `SET POWER ON/OFF request received from pid N (proc)` (ControlCenter = user). Use `/usr/bin/log`: zsh's `log` builtin shadows it.
