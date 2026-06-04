import Foundation
import Combine

/// User configuration, persisted in UserDefaults.
///
/// Both interface lists use an **opt-out** model: anything not explicitly
/// disabled is enabled. So a newly-attached wired adapter automatically counts
/// as a trigger, and a new Wi-Fi adapter is automatically controlled.
public final class AppSettings: ObservableObject {

    private let defaults: UserDefaults

    @Published public var autoEnabled: Bool {
        didSet { defaults.set(autoEnabled, forKey: Keys.autoEnabled) }
    }

    /// Wired BSD names that are NOT used as triggers.
    @Published public var disabledWired: Set<String> {
        didSet { defaults.set(Array(disabledWired), forKey: Keys.disabledWired) }
    }

    /// Wi-Fi BSD names that are NOT controlled.
    @Published public var disabledWiFi: Set<String> {
        didSet { defaults.set(Array(disabledWiFi), forKey: Keys.disabledWiFi) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.autoEnabled = (defaults.object(forKey: Keys.autoEnabled) as? Bool) ?? true
        self.disabledWired = Set(defaults.stringArray(forKey: Keys.disabledWired) ?? [])
        self.disabledWiFi = Set(defaults.stringArray(forKey: Keys.disabledWiFi) ?? [])
    }

    public func wiredEnabled(_ bsd: String) -> Bool { !disabledWired.contains(bsd) }
    public func wifiEnabled(_ bsd: String) -> Bool { !disabledWiFi.contains(bsd) }

    public func setWiredEnabled(_ bsd: String, _ enabled: Bool) {
        if enabled { disabledWired.remove(bsd) } else { disabledWired.insert(bsd) }
    }

    public func setWiFiEnabled(_ bsd: String, _ enabled: Bool) {
        if enabled { disabledWiFi.remove(bsd) } else { disabledWiFi.insert(bsd) }
    }

    private enum Keys {
        static let autoEnabled = "autoEnabled"
        static let disabledWired = "disabledWired"
        static let disabledWiFi = "disabledWiFi"
    }
}
