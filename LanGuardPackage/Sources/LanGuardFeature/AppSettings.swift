import Foundation
import Combine

/// User configuration, persisted in UserDefaults.
///
/// Physical wired adapters and Wi-Fi adapters use an **opt-out** model: anything
/// not explicitly disabled is enabled, so a newly-attached real adapter is picked
/// up automatically. **Virtual** wired adapters (bridge/VPN/VM/tunnel) use an
/// **opt-in** model: off by default, so they never pin Wi-Fi off by accident.
public final class AppSettings: ObservableObject {

    private let defaults: UserDefaults

    @Published public var autoEnabled: Bool {
        didSet { defaults.set(autoEnabled, forKey: Keys.autoEnabled) }
    }

    @Published public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    /// Physical wired BSD names that are NOT used as triggers (opt-out).
    @Published public var disabledWired: Set<String> {
        didSet { defaults.set(Array(disabledWired), forKey: Keys.disabledWired) }
    }

    /// Virtual wired BSD names the user explicitly enabled as triggers (opt-in).
    @Published public var enabledVirtual: Set<String> {
        didSet { defaults.set(Array(enabledVirtual), forKey: Keys.enabledVirtual) }
    }

    /// Wi-Fi BSD names that are NOT controlled (opt-out).
    @Published public var disabledWiFi: Set<String> {
        didSet { defaults.set(Array(disabledWiFi), forKey: Keys.disabledWiFi) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.autoEnabled = (defaults.object(forKey: Keys.autoEnabled) as? Bool) ?? true
        self.notificationsEnabled = (defaults.object(forKey: Keys.notificationsEnabled) as? Bool) ?? true
        self.disabledWired = Set(defaults.stringArray(forKey: Keys.disabledWired) ?? [])
        self.enabledVirtual = Set(defaults.stringArray(forKey: Keys.enabledVirtual) ?? [])
        self.disabledWiFi = Set(defaults.stringArray(forKey: Keys.disabledWiFi) ?? [])
    }

    /// Is this wired interface an active trigger? Virtual → opt-in, physical → opt-out.
    public func wiredEnabled(_ iface: NetInterface) -> Bool {
        if iface.isVirtual { return enabledVirtual.contains(iface.bsdName) }
        return !disabledWired.contains(iface.bsdName)
    }

    public func setWiredEnabled(_ iface: NetInterface, _ enabled: Bool) {
        if iface.isVirtual {
            if enabled { enabledVirtual.insert(iface.bsdName) } else { enabledVirtual.remove(iface.bsdName) }
        } else {
            if enabled { disabledWired.remove(iface.bsdName) } else { disabledWired.insert(iface.bsdName) }
        }
    }

    public func wifiEnabled(_ bsd: String) -> Bool { !disabledWiFi.contains(bsd) }

    public func setWiFiEnabled(_ bsd: String, _ enabled: Bool) {
        if enabled { disabledWiFi.remove(bsd) } else { disabledWiFi.insert(bsd) }
    }

    private enum Keys {
        static let autoEnabled = "autoEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let disabledWired = "disabledWired"
        static let enabledVirtual = "enabledVirtual"
        static let disabledWiFi = "disabledWiFi"
    }
}
