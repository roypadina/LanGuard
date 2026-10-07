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

    /// Banner when the LAN is unplugged and Wi-Fi turns back on.
    @Published public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    /// Banner when traffic has moved to the LAN and Wi-Fi turned off.
    @Published public var notifyMovedToLAN: Bool {
        didSet { defaults.set(notifyMovedToLAN, forKey: Keys.notifyMovedToLAN) }
    }

    /// Floating progress window while Switch to Wi-Fi runs (closes itself when done).
    @Published public var switchProgressPopup: Bool {
        didSet { defaults.set(switchProgressPopup, forKey: Keys.switchProgressPopup) }
    }

    /// "Safe to unplug LAN" popup at the end of Switch to Wi-Fi.
    @Published public var safeToUnplugPopup: Bool {
        didSet { defaults.set(safeToUnplugPopup, forKey: Keys.safeToUnplugPopup) }
    }

    @Published public var menuIconStyle: MenuIconStyle {
        didSet { defaults.set(menuIconStyle.rawValue, forKey: Keys.menuIconStyle) }
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

    /// Connection protection (stable address that follows LAN/Wi-Fi). Off until enabled.
    @Published public var protectionEnabled: Bool {
        didSet { defaults.set(protectionEnabled, forKey: Keys.protectionEnabled) }
    }

    /// Networks (router IP@MAC) where protection applies: learned when LAN + Wi-Fi share a router,
    /// or ticked by hand.
    @Published public private(set) var protectedNetworks: Set<String>

    /// Networks the user explicitly switched off: never re-learned.
    @Published public private(set) var disabledNetworks: Set<String>

    /// Learned (from the protection queue) or user toggle; `byUser: false` never overrides a user "off".
    public func setProtected(_ net: String, _ on: Bool, byUser: Bool = false) {
        DispatchQueue.main.async {
            if on { self.protectedNetworks.insert(net) } else { self.protectedNetworks.remove(net) }
            if byUser { if on { self.disabledNetworks.remove(net) } else { self.disabledNetworks.insert(net) } }
            self.defaults.set(Array(self.protectedNetworks), forKey: Keys.protectedNetworks)
            self.defaults.set(Array(self.disabledNetworks), forKey: Keys.disabledNetworks)
        }
    }

    /// Remembered stable address per network, and "paused until" per network (UserDefaults dicts;
    /// thread-safe, read from the protection queue).
    func stableAddress(_ net: String) -> String? { (defaults.dictionary(forKey: Keys.stableAddresses) as? [String: String])?[net] }
    func setStableAddress(_ net: String, _ a: String) {
        var d = (defaults.dictionary(forKey: Keys.stableAddresses) as? [String: String]) ?? [:]
        d[net] = a; defaults.set(d, forKey: Keys.stableAddresses)
    }
    func hold(_ net: String) -> Date? {
        ((defaults.dictionary(forKey: Keys.holds) as? [String: Double])?[net]).map(Date.init(timeIntervalSince1970:))
    }
    func setHold(_ net: String, until: Date) {
        var d = (defaults.dictionary(forKey: Keys.holds) as? [String: Double]) ?? [:]
        d[net] = until.timeIntervalSince1970; defaults.set(d, forKey: Keys.holds)
    }

    /// Global "Switch to Wi-Fi" shortcut (recorded in Settings).
    @Published public var hotKey: HotKeyCombo {
        didSet { defaults.set(try? JSONEncoder().encode(hotKey), forKey: Keys.hotKey) }
    }

    /// Write a diagnostic log to ~/Library/Logs/LanGuard (off by default).
    /// Key must match `Log.enabledKey`.
    @Published public var debugLoggingEnabled: Bool {
        didSet { defaults.set(debugLoggingEnabled, forKey: Keys.debugLoggingEnabled) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.autoEnabled = (defaults.object(forKey: Keys.autoEnabled) as? Bool) ?? true
        let notify = (defaults.object(forKey: Keys.notificationsEnabled) as? Bool) ?? true
        self.notificationsEnabled = notify
        // Was covered by the single notifications switch before → inherit its value.
        self.notifyMovedToLAN = (defaults.object(forKey: Keys.notifyMovedToLAN) as? Bool) ?? notify
        self.safeToUnplugPopup = (defaults.object(forKey: Keys.safeToUnplugPopup) as? Bool) ?? true
        self.switchProgressPopup = (defaults.object(forKey: Keys.switchProgressPopup) as? Bool) ?? true
        self.menuIconStyle = MenuIconStyle(rawValue: defaults.string(forKey: Keys.menuIconStyle) ?? "") ?? .symbol
        self.disabledWired = Set(defaults.stringArray(forKey: Keys.disabledWired) ?? [])
        self.enabledVirtual = Set(defaults.stringArray(forKey: Keys.enabledVirtual) ?? [])
        self.disabledWiFi = Set(defaults.stringArray(forKey: Keys.disabledWiFi) ?? [])
        self.debugLoggingEnabled = defaults.bool(forKey: Keys.debugLoggingEnabled)
        self.protectionEnabled = defaults.bool(forKey: Keys.protectionEnabled)
        self.protectedNetworks = Set(defaults.stringArray(forKey: Keys.protectedNetworks) ?? [])
        self.disabledNetworks = Set(defaults.stringArray(forKey: Keys.disabledNetworks) ?? [])
        self.hotKey = defaults.data(forKey: Keys.hotKey)
            .flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) } ?? .default
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
        static let notifyMovedToLAN = "notifyMovedToLAN"
        static let safeToUnplugPopup = "safeToUnplugPopup"
        static let hotKey = "hotKey"
        static let protectionEnabled = "protectionEnabled"
        static let protectedNetworks = "protectedNetworks"
        static let disabledNetworks = "disabledNetworks"
        static let stableAddresses = "stableAddresses"
        static let holds = "protectionHolds"
        static let switchProgressPopup = "switchProgressPopup"
        static let menuIconStyle = "menuIconStyle"
        static let disabledWired = "disabledWired"
        static let enabledVirtual = "enabledVirtual"
        static let disabledWiFi = "disabledWiFi"
        static let debugLoggingEnabled = "debugLoggingEnabled"
    }
}
