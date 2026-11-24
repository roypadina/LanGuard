import Foundation
import SystemConfiguration
import AppKit

/// Watches for network-state changes (link up/down, IP changes) and system wake,
/// and exposes per-interface link-active reads. Calls `onChange` on the main thread.
public final class NetworkMonitor {

    /// Invoked (main thread) whenever the network state changes or the machine wakes.
    public var onChange: () -> Void = {}

    private var store: SCDynamicStore?

    /// Coalesce bursts of SCDynamicStore callbacks and absorb transient link
    /// flaps (a USB/Thunderbolt dock's Ethernet drops briefly on display sleep).
    /// A real plug/unplug still settles within the debounce window.
    private var pendingEvaluate: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 1.5

    /// While the machine is asleep we ignore link changes entirely: the dock
    /// powers its Ethernet down on sleep and back up on wake, which otherwise
    /// looks like an unplug→replug and spams toggles/notifications.
    private var suspended = false
    private let wakeSettleInterval: TimeInterval
    /// The post-wake settle; cancelled when the Mac sleeps again before it fires.
    private var pendingWakeSettle: DispatchWorkItem?
    /// Source of sleep/wake notifications (injected by tests).
    private let notificationCenter: NotificationCenter

    public init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
                wakeSettleInterval: TimeInterval = 4.0) {
        self.notificationCenter = notificationCenter
        self.wakeSettleInterval = wakeSettleInterval
    }

    public func start() {
        var ctx = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info = info else { return }
            let monitor = Unmanaged<NetworkMonitor>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { monitor.networkChanged() }
        }

        guard let store = SCDynamicStoreCreate(nil, "com.roy.languard" as CFString, callback, &ctx) else {
            return
        }
        self.store = store

        // Fire on link state, per-interface IPv4, and global IPv4/DNS changes.
        let patterns = [
            "State:/Network/Interface/[^/]+/Link",
            "State:/Network/Interface/[^/]+/IPv4",
            "State:/Network/Global/IPv4",
            "State:/Network/Global/DNS",
        ] as CFArray
        SCDynamicStoreSetNotificationKeys(store, nil, patterns)

        if let src = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }

        observeSleepWake()
    }

    /// Split from `start()` so tests can drive sleep/wake without an SCDynamicStore.
    func observeSleepWake() {
        // Sleep/wake handling. A docked Mac's Ethernet link drops on sleep and
        // returns on wake; acting on those fires spurious toggles + notifications.
        // So: ignore link changes while asleep, and after wake wait for the
        // network to settle, then evaluate once. A genuine undock-while-asleep is
        // still caught — the settled post-wake state reads as a real edge.
        let nc = notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Log.write("willSleep → suspend (ignore link changes while asleep)")
            self?.suspended = true
            self?.pendingEvaluate?.cancel()
            // A wake that hasn't settled yet must not resume us mid-churn after the next wake.
            self?.pendingWakeSettle?.cancel()
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Log.write("didWake → settle \(self.wakeSettleInterval)s, then evaluate once")
            // Stay suspended through the post-wake network churn, then resume + evaluate once.
            self.pendingWakeSettle?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                Log.write("wake settle done → resume + evaluate")
                self.suspended = false
                self.pendingEvaluate?.cancel()
                self.onChange()
            }
            self.pendingWakeSettle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + self.wakeSettleInterval, execute: work)
        }
    }

    /// A raw SCDynamicStore change. Dropped while asleep; otherwise debounced so a
    /// burst of key changes (or a brief link flap) collapses into a single evaluate.
    private func networkChanged() {
        guard !suspended else {
            Log.write("net-change ignored (asleep)")
            return
        }
        Log.write("net-change → debounce \(debounceInterval)s")
        pendingEvaluate?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingEvaluate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    /// True if the interface currently has an active physical link.
    /// Prefers the SystemConfiguration Link key; falls back to ifconfig.
    public func linkActive(_ bsd: String) -> Bool {
        if let store = store {
            let key = "State:/Network/Interface/\(bsd)/Link" as CFString
            if let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
               let active = dict[kSCPropNetLinkActive as String] as? Bool {
                return active
            }
        }
        return Self.ifconfigActive(bsd)
    }

    /// Fallback link check via `ifconfig <dev>` → "status: active".
    private static func ifconfigActive(_ bsd: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        proc.arguments = [bsd]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.contains("status: active")
    }
}
