import Foundation
import SystemConfiguration
import AppKit

/// Watches for network-state changes (link up/down, IP changes) and system wake,
/// and exposes per-interface link-active reads. Calls `onChange` on the main thread.
public final class NetworkMonitor {

    /// Invoked (main thread) whenever the network state changes or the machine wakes.
    public var onChange: () -> Void = {}

    private var store: SCDynamicStore?

    public init() {}

    public func start() {
        var ctx = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info = info else { return }
            let monitor = Unmanaged<NetworkMonitor>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { monitor.onChange() }
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

        // Re-evaluate on wake — covers "WiFi got toggled while asleep" case.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.onChange()
        }
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
