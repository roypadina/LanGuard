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

    private var bag = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    public init() {
        let settings = AppSettings()
        let monitor = NetworkMonitor()
        self.settings = settings
        self.monitor = monitor

        let deps = ToggleEngine.Dependencies(
            activeWiredNames: { [monitor] in
                InterfaceCatalog.wired()
                    .map(\.bsdName)
                    .filter { settings.wiredEnabled($0) }
                    .filter { monitor.linkActive($0) }
            },
            wifiTargets: {
                InterfaceCatalog.wifi()
                    .map(\.bsdName)
                    .filter { settings.wifiEnabled($0) }
            },
            setWiFiPower: { on, names in WiFiController.setPower(on, interfaces: names) },
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
    }

    /// Called once at launch.
    public func start() {
        LegacyCleanup.run()

        // First run: honour the user's "autostart" choice.
        if !defaults.bool(forKey: "didInitialSetup") {
            LoginItem.setEnabled(true)
            defaults.set(true, forKey: "didInitialSetup")
        }

        monitor.onChange = { [weak self] in self?.engine.evaluate() }
        monitor.start()
        engine.evaluate()
    }

    // MARK: - View-facing helpers

    public func setAuto(_ on: Bool) {
        settings.autoEnabled = on
        if on { engine.reapply() } else { engine.evaluate() }
    }

    /// Call after the user changes which interfaces are selected.
    public func selectionChanged() {
        engine.reapply()
    }

    public func linkActive(_ bsd: String) -> Bool { monitor.linkActive(bsd) }
    public func wifiPoweredOn(_ bsd: String) -> Bool { WiFiController.isPoweredOn(bsd) }

    /// SF Symbol for the menu-bar icon, reflecting current state.
    public var menuSymbol: String {
        if !settings.autoEnabled { return "pause.circle" }
        return engine.wiredUp ? "cable.connector" : "wifi"
    }

    public var statusLine: String {
        let wired = engine.wiredUp ? engine.activeWired.joined(separator: ", ") : "none"
        return "Wired: \(wired)  ·  Wi-Fi: \(engine.wifiOn ? "on" : "off")"
    }
}
