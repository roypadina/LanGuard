import Foundation
import Combine

/// Edge-based Wi-Fi toggling logic.
///
/// The engine acts only on **transitions** of the wired-link state:
///  - wired goes up   → turn selected Wi-Fi OFF
///  - wired goes down → turn selected Wi-Fi ON
///
/// Between edges it never touches Wi-Fi, so a manual Wi-Fi change made while the
/// wired state is unchanged is respected until the next unplug/replug. The last
/// wired state is persisted so a transition that happened across sleep is seen
/// as an edge on wake.
///
/// All collaborators are injected, so the core logic is unit-testable without
/// real hardware.
public final class ToggleEngine: ObservableObject {

    public struct Dependencies {
        /// Enabled wired BSD names that currently have an active link.
        public var activeWiredNames: () -> [String]
        /// Enabled Wi-Fi BSD names to control.
        public var wifiTargets: () -> [String]
        /// Apply power to the given Wi-Fi interfaces.
        public var setWiFiPower: (_ on: Bool, _ interfaces: [String]) -> Void
        /// Whether any controlled Wi-Fi is currently powered on (for status).
        public var anyWiFiOn: () -> Bool
        /// Master switch.
        public var autoEnabled: () -> Bool
        /// Persist / load the last seen wired state across launches.
        public var saveLastWired: (Bool?) -> Void
        public var loadLastWired: () -> Bool?

        public init(
            activeWiredNames: @escaping () -> [String],
            wifiTargets: @escaping () -> [String],
            setWiFiPower: @escaping (Bool, [String]) -> Void,
            anyWiFiOn: @escaping () -> Bool,
            autoEnabled: @escaping () -> Bool,
            saveLastWired: @escaping (Bool?) -> Void,
            loadLastWired: @escaping () -> Bool?
        ) {
            self.activeWiredNames = activeWiredNames
            self.wifiTargets = wifiTargets
            self.setWiFiPower = setWiFiPower
            self.anyWiFiOn = anyWiFiOn
            self.autoEnabled = autoEnabled
            self.saveLastWired = saveLastWired
            self.loadLastWired = loadLastWired
        }
    }

    // Published status for the UI / menu bar.
    @Published public private(set) var wiredUp: Bool = false
    @Published public private(set) var activeWired: [String] = []
    @Published public private(set) var wifiOn: Bool = false

    private let deps: Dependencies
    private var lastWired: Bool?

    public init(dependencies: Dependencies) {
        self.deps = dependencies
        self.lastWired = dependencies.loadLastWired()
    }

    /// React to a network/wake/launch event. Acts only on a wired-state edge.
    public func evaluate() {
        let active = deps.activeWiredNames()
        let wired = !active.isEmpty
        let prev = lastWired

        if deps.autoEnabled() {
            let targets = deps.wifiTargets()
            if prev == nil {
                // First evaluation since (re)start/reapply: enforce only the
                // "wired up → Wi-Fi off" case. If no wired, leave Wi-Fi alone.
                if wired { deps.setWiFiPower(false, targets) }
            } else if wired != prev {
                deps.setWiFiPower(/* on: */ !wired, targets)
            }
        }

        lastWired = wired
        deps.saveLastWired(wired)
        publishStatus(wired: wired, active: active)
    }

    /// Force a fresh enforcement (used when auto is re-enabled or the
    /// interface selection changes): clears edge memory then evaluates.
    public func reapply() {
        lastWired = nil
        deps.saveLastWired(nil)
        evaluate()
    }

    private func publishStatus(wired: Bool, active: [String]) {
        let on = deps.anyWiFiOn()
        if Thread.isMainThread {
            wiredUp = wired; activeWired = active; wifiOn = on
        } else {
            DispatchQueue.main.async {
                self.wiredUp = wired; self.activeWired = active; self.wifiOn = on
            }
        }
    }
}
