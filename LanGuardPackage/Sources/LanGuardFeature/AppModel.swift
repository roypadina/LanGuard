import Foundation
import Combine
import AppKit

/// Top-level app state: wires Settings + NetworkMonitor + WiFiController into the
/// ToggleEngine, owns lifecycle, and exposes view-facing helpers.
public final class AppModel: ObservableObject {

    public static let shared = AppModel()

    public let settings: AppSettings
    public let monitor: NetworkMonitor
    public let engine: ToggleEngine
    public let handover: Handover
    public let protection: Protection

    private var bag = Set<AnyCancellable>()

    public init() {
        let settings = AppSettings()
        let monitor = NetworkMonitor()
        let protection = Protection(settings: settings)
        let handover = Handover(settings: settings, protection: protection)
        self.settings = settings
        self.monitor = monitor
        self.handover = handover
        self.protection = protection

        let deps = ToggleEngine.Dependencies(
            activeWiredNames: { [monitor] in
                InterfaceCatalog.wired()
                    .filter { settings.wiredEnabled($0) }
                    .map(\.bsdName)
                    .filter { monitor.linkActive($0) }
            },
            wifiTargets: {
                InterfaceCatalog.wifi()
                    .map(\.bsdName)
                    .filter { settings.wifiEnabled($0) }
            },
            setWiFiPower: { on, names in
                guard on else {
                    // Wi-Fi goes off only after traffic has moved to the LAN (see Handover).
                    handover.toLAN(names, lanName: {
                        InterfaceCatalog.wired()
                            .first { settings.wiredEnabled($0) && monitor.linkActive($0.bsdName) }?
                            .displayName ?? "Wired LAN"
                    })
                    return
                }
                // Only touch interfaces whose power actually differs, and only
                // notify if something really changed — no redundant banners.
                let toChange = names.filter { !WiFiController.isPoweredOn($0) }
                Log.write("setWiFiPower(on: true) targets=\(names) changing=\(toChange)")
                guard !toChange.isEmpty else { return }
                WiFiController.setPower(true, interfaces: toChange)
                guard settings.notificationsEnabled else { return }
                Notifier.post(title: "Wi-Fi on",
                              body: "Wired LAN disconnected — Wi-Fi turned back on.")
            },
            anyWiFiOn: {
                InterfaceCatalog.wifi()
                    .map(\.bsdName)
                    .filter { settings.wifiEnabled($0) }
                    .contains { WiFiController.isPoweredOn($0) }
            },
            autoEnabled: { settings.autoEnabled },
            saveLastWired: { value in
                UserDefaults.standard.set(value.map { $0 ? 1 : 0 } ?? -1, forKey: "lastWired")
            },
            loadLastWired: {
                guard let raw = UserDefaults.standard.object(forKey: "lastWired") as? Int, raw >= 0
                else { return nil }
                return raw == 1
            }
        )
        self.engine = ToggleEngine(dependencies: deps)

        // Re-publish child changes so views observing AppModel refresh.
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        engine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        protection.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        handover.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    /// Called once at launch.
    public func start() {
        // One instance only: two would fight over the stable address (Fable gate-1 #9).
        let me = NSRunningApplication.current
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains(where: { $0 != me }) {
            Log.write("another LanGuard is running → quit")
            NSApp.terminate(nil)
            return
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        Log.write("=== LanGuard \(version) start (debug logging on) ===")
        LegacyCleanup.run()
        Notifier.requestAuthorization()

        // Auto-register the login item for the current bundle path every launch.
        // Self-heals after a move; prompts the user if macOS needs approval.
        switch LoginItem.ensureRegistered() {
        case .reRegisterMoved:
            LoginItem.notifyReRegisteredAfterMove()
        case .register, .none:
            LoginItem.promptForApprovalIfNeeded()
        }

        monitor.onChange = { [weak self] in self?.evaluate() }
        monitor.start()
        evaluate()
        HotKey.start(settings.hotKey) { [weak self] in self?.switchToWiFi() }
        protection.start()
    }


    public func setProtection(_ on: Bool) {
        settings.protectionEnabled = on
        protection.reconcile()
    }

    /// Current network in/out of the protected set ("Protect this network").
    public func setProtectThisNetwork(_ on: Bool) {
        guard let net = protection.currentNetwork else { return }
        settings.setProtected(net, on, byUser: true)
        DispatchQueue.main.async { self.protection.reconcile() }
    }

    public func setHotKey(_ combo: HotKeyCombo) {
        settings.hotKey = combo
        HotKey.register(combo)
    }

    private func evaluate() {
        engine.evaluate()
        // Also when auto-toggle is off: a "Switch to Wi-Fi" still needs closing out.
        if !engine.wiredUp { handover.lanUnplugged() } else if !engine.wifiOn { handover.wifiTurnedOff() }
    }

    /// "Switch to Wi-Fi" (menu + global shortcut): move traffic to Wi-Fi so the LAN can be unplugged.
    /// Pressed again while switched (LAN still plugged in): back to LAN.
    public func switchToWiFi() {
        guard engine.wiredUp else { return }
        if handover.switchedToWiFi { return backToLAN() }
        let wifi = InterfaceCatalog.wifi().map(\.bsdName).filter { settings.wifiEnabled($0) }
        handover.toWiFi(wifi, wired: engine.activeWired)
    }

    /// Undo a "Switch to Wi-Fi": protection moves back to the LAN, then (auto-toggle on) Wi-Fi goes
    /// off the usual make-before-break way (Handover.toLAN).
    public func backToLAN() {
        Log.write("backToLAN")
        handover.reset()
        protection.reconcile()
        if settings.autoEnabled { engine.reapply() }
    }

    // MARK: - View-facing helpers

    public func setAuto(_ on: Bool) {
        settings.autoEnabled = on
        handover.reset()
        protection.reconcile()
        if on { engine.reapply() } else { engine.evaluate() }
    }

    /// Call after the user changes which interfaces are selected.
    public func selectionChanged() {
        engine.reapply()
    }

    public func linkActive(_ bsd: String) -> Bool { monitor.linkActive(bsd) }
    public func wifiPoweredOn(_ bsd: String) -> Bool { WiFiController.isPoweredOn(bsd) }

    /// Current state shown in the menu bar (LAN / Wi-Fi / paused).
    public var menuState: MenuState {
        MenuState.from(autoEnabled: settings.autoEnabled, wiredUp: engine.wiredUp)
    }

    public var statusLine: String {
        let wired = engine.wiredUp ? engine.activeWired.joined(separator: ", ") : "none"
        return "Wired: \(wired)  ·  Wi-Fi: \(engine.wifiOn ? "on" : "off")"
    }
}
