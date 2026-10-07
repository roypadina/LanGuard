import Foundation
import SystemConfiguration
import Network

/// Connection protection: keeps a stable per-network address A on whichever link is active
/// (wired preferred, Wi-Fi when the user switched or the LAN is gone) via the root helper, so
/// connections survive LAN <-> Wi-Fi switches. The helper's guardian tears everything down on its
/// own when the kernel state is not sane; this class only decides where A should live.
///
/// Safety rules (Fable gate-1): protect only networks where LAN and Wi-Fi were seen on the same
/// router (or the user ticked "Protect this network"); after the guardian tears down, wait 30 min
/// before protecting that network again; panic is sticky until re-enabled explicitly.
public final class Protection: ObservableObject {

    /// Menu/Settings status line.
    @Published public private(set) var status = "Off"
    /// Where A currently lives (nil = not protecting).
    @Published public private(set) var activeIface: String?
    /// Current network's signature (router IP + MAC), for the "Protect this network" toggle.
    @Published public private(set) var currentNetwork: String?

    /// Set by Switch-to-Wi-Fi: A should live on Wi-Fi even while the LAN is plugged in. Main thread only.
    public var preferWiFi = false

    /// Everything reconcile needs from settings, captured on the main thread so the protection
    /// queue never reads main-thread state (gate-3 #8).
    struct Snapshot {
        var enabled: Bool, preferWiFi: Bool, wired: [String], protected: Set<String>, disabled: Set<String>
    }
    private func snapshot() -> Snapshot {
        Snapshot(enabled: settings.protectionEnabled, preferWiFi: preferWiFi,
                 wired: InterfaceCatalog.wired().filter { settings.wiredEnabled($0) }.map(\.bsdName),
                 protected: settings.protectedNetworks, disabled: settings.disabledNetworks)
    }
    private var scheduled = false   // main thread: coalesces bursts of reconcile requests (gate-3 #9)
    private var dirty = false       // main thread: a request arrived while one was pending → run again

    private let settings: AppSettings
    private let queue = DispatchQueue(label: "com.roy.languard.protection") // serial: one helper call at a time
    private var store: SCDynamicStore?
    private var timer: Timer?
    private var expectingState = false
    private var shownOn = false     // queue-owned: last published status was "On …"
    private var guardianStaleSince: TimeInterval?   // queue-owned; systemUptime (pauses during sleep)
    private static let holdSeconds: TimeInterval = 30 * 60

    init(settings: AppSettings) { self.settings = settings }

    /// Launch: adopt helper state left by a previous run, then watch links without debounce.
    func start() {
        let snap = snapshot()
        queue.async {
            if NetHelper.state() != nil {
                self.expectingState = NetHelper.run(["adopt", "\(getpid())"]) == NetHelper.Exit.ok.rawValue
            }
            self.reconcileLocked(snap)
        }
        var ctx = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                        retain: nil, release: nil, copyDescription: nil)
        let cb: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            Unmanaged<Protection>.fromOpaque(info).takeUnretainedValue().reconcile()
        }
        if let s = SCDynamicStoreCreate(nil, "com.roy.languard.protection" as CFString, cb, &ctx) {
            SCDynamicStoreSetNotificationKeys(s, nil, ["State:/Network/Interface/en[0-9]+/Link",
                                                       "State:/Network/Interface/en[0-9]+/IPv4",
                                                       "State:/Network/Global/IPv4"] as CFArray)
            if let src = SCDynamicStoreCreateRunLoopSource(nil, s, 0) {
                CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            }
            store = s
        }
        // Also catch guardian teardowns / VPN changes that fire no link event.
        // Common modes: keep running while a menu or modal alert is open (gate-3 #11).
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.reconcile() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Re-evaluate where A should live. Cheap when nothing changed. Call on the main thread.
    public func reconcile() {
        guard !scheduled else { dirty = true; return }
        scheduled = true
        let snap = snapshot()
        queue.async {
            self.reconcileLocked(snap)
            DispatchQueue.main.async {
                self.scheduled = false
                if self.dirty { self.dirty = false; self.reconcile() }   // fresh snapshot for the late request
            }
        }
    }

    /// For hand-overs that must know the result (Switch to Wi-Fi, LAN return): reconcile, then
    /// return the interface A lives on (nil = not protecting). Runs off the main thread.
    @MainActor func settle() async -> String? {
        let snap = snapshot()
        return await withCheckedContinuation { cont in
            queue.async { self.reconcileLocked(snap); cont.resume(returning: NetHelper.state()?["IFACE"]) }
        }
    }

    /// Quit / disable: remove everything.
    func stop() { queue.sync { _ = NetHelper.run(["down"]); expectingState = false; publish("Off", nil) } }

    /// PANIC menu item. Sticky until `rearm()`.
    public func panic() {
        // Not on `queue`: a reconcile stuck in a helper call must never block panic (gate-2 #3).
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = NetHelper.panic()
            self.queue.async { self.expectingState = false }
            self.publish(ok ? "Off — panic. Normal networking restored." : "Panic FAILED — reboot restores networking", nil)
            Notifier.post(title: ok ? "LanGuard protection off" : "LanGuard panic failed",
                          body: ok ? "Normal networking restored (panic)." : "Use the Raycast script, the README one-liner, or reboot.")
        }
    }

    /// Explicit re-enable after a panic.
    public func rearm() {
        let snap = snapshot()
        queue.async { _ = NetHelper.run(["arm"]); self.reconcileLocked(snap) }
    }

    // MARK: - Core

    private func reconcileLocked(_ snap: Snapshot) {
        guard snap.enabled, NetHelper.installed else {
            if NetHelper.state() != nil { NetHelper.run(["down"]) }
            expectingState = false
            return publish(NetHelper.installed ? "Off" : "Off — helper not installed", nil)
        }
        if NetHelper.panicked {
            if NetHelper.state() != nil { NetHelper.run(["down"]) }      // panic raced an up/move: enforce it
            expectingState = false
            return publish("Off — panic. Re-enable from the menu.", nil)
        }
        if NetHelper.guardianRunning {
            guardianStaleSince = nil
        } else {
            // Never ARM without a fresh guardian tick (helper exit 9). If protecting, tear down only after the
            // tick stayed stale > 20 s — right after wake it is stale until launchd's next run (gate-2 final #2).
            // Uptime, not wall clock: time asleep must not count (the guardian can't tick while asleep).
            let now = ProcessInfo.processInfo.systemUptime
            let since = guardianStaleSince ?? now; guardianStaleSince = since
            if NetHelper.state() != nil {
                guard now - since > 20 else { return }
                NetHelper.run(["down"])
            }
            expectingState = false
            return publish("Off — guardian not running (allow LanGuard in System Settings › General › Login Items)", nil)
        }

        var st = NetHelper.state()

        let wired = snap.wired.first { Net.usable($0) }
        let wifi = InterfaceCatalog.wifi().map(\.bsdName).first { Net.usable($0) }
        guard let target = Self.target(preferWiFi: snap.preferWiFi, wired: wired, wifi: wifi),
              let router = Net.router(target) else {
            return publish(st == nil ? "Waiting for a network…" : "Moving…", st?["IFACE"])
        }
        guard let net = Net.signature(router: router, iface: target) else {
            // Router MAC unreadable = macOS Local Network privacy is hiding the ARP table from LanGuard.
            // Never arm blind (the helper's free-address check relies on ARP too). Ask for access.
            Net.requestLocalNetworkAccess(router)
            if st == nil {
                return publish("Waiting for router identity — if this persists: Settings › Protection › Update helper", nil)
            }
            return publish("Moving…", st?["IFACE"])
        }
        DispatchQueue.main.async { self.currentNetwork = net }

        if expectingState, st == nil {
            // The guardian tore protection down. Hold 30 min only when it was unhealthy — not for an
            // undock, a link change, a network change or a VPN (gate-2 #6).
            expectingState = false
            if NetHelper.teardownReason == "unhealthy" {
                settings.setHold(net, until: Date().addingTimeInterval(Self.holdSeconds))
                Notifier.post(title: "LanGuard protection paused",
                              body: "No internet through the stable address — normal networking for 30 min.")
            }
        }

        // Learn: LAN and Wi-Fi on the same router = a network where switching happens.
        // Never re-learn a network the user switched off (gate-3 #6).
        let learned = !snap.disabled.contains(net) && wired != nil && wifi != nil && Net.router(wired!) == Net.router(wifi!)
        if learned, !snap.protected.contains(net) { settings.setProtected(net, true) }
        guard learned || snap.protected.contains(net) else {
            if st != nil { NetHelper.run(["down"]); expectingState = false }
            return publish("Off on this network", nil)
        }
        if let until = settings.hold(net), until > Date() {
            if st != nil { NetHelper.run(["down"]); expectingState = false }
            return publish("Paused until \(Self.timeFormatter.string(from: until))", nil)
        }
        if let s = st, s["GW"] != router {                          // network changed under us
            NetHelper.run(["down"]); st = nil
        }

        if let s = st {
            if s["IFACE"] != target {
                let rc = NetHelper.run(["move", target])
                // noState = the guardian tore down meanwhile: keep expecting so the hold logic sees it (gate-2 #7).
                if rc == NetHelper.Exit.noState.rawValue { return }
            }
        } else {
            up(target, router: router, net: net)
        }
        let now = NetHelper.state()
        expectingState = now != nil
        if let a = now?["A"], let i = now?["IFACE"] { publish("On · \(a) on \(i)", i) }
        else if shownOn { publish("Off", nil) }                 // move failed and helper tore down (gate-3 #10)
    }

    /// Bring protection up on `iface`, trying the remembered address first, then free candidates.
    private func up(_ iface: String, router: String, net: String) {
        guard let ip = Net.address(iface), let mask = Net.mask(iface) else { return }
        var candidates = Self.candidates(ip: ip, mask: mask, exclude: [ip, router])
        if let saved = settings.stableAddress(net), candidates.contains(saved) {
            candidates.removeAll { $0 == saved }
            candidates.insert(saved, at: 0)
        }
        for a in candidates.prefix(8) {
            let rc = NetHelper.run(["up", iface, a, "\(getpid())"])
            switch NetHelper.Exit(rawValue: rc) {
            case .ok: settings.setStableAddress(net, a); return
            case .taken: continue
            case .verifyFailed:                                                 // no retry loop: pause 5 min (gate-3 #5)
                settings.setHold(net, until: Date().addingTimeInterval(5 * 60))
                return publish("Off — routes could not be verified; retrying in 5 min", nil)
            case .conflict: return publish("Paused — a VPN or exit node owns routing", nil)
            case .otherInstance: return publish("Off — another LanGuard is protecting", nil)
            case .noGuardian: return publish("Off — guardian not running", nil)
            case .panicked: return publish("Off — panic. Re-enable from the menu.", nil)
            default: return publish("Off — helper error \(rc)", nil)
            }
        }
        settings.setHold(net, until: Date().addingTimeInterval(5 * 60))
        publish("Off — no free address found; retrying in 5 min", nil)
    }

    private func publish(_ text: String, _ iface: String?) {
        shownOn = text.hasPrefix("On")
        DispatchQueue.main.async { self.status = text; self.activeIface = iface }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    // MARK: - Pure (unit-tested)

    /// Wired wins unless the user switched to Wi-Fi; otherwise whatever is usable.
    static func target(preferWiFi: Bool, wired: String?, wifi: String?) -> String? {
        preferWiFi ? (wifi ?? wired) : (wired ?? wifi)
    }

    /// Free-address candidates from the top of the subnet down (skips network, broadcast, excludes).
    static func candidates(ip: String, mask: String, exclude: Set<String>, count: Int = 20) -> [String] {
        guard let i = Net.int(ip), let m = Net.int(mask), m != 0xFFFF_FFFF else { return [] }
        let broadcast = (i & m) | ~m
        var out: [String] = []
        var a = broadcast &- 1
        while (out.count < count) && (a > (i & m)) {
            let s = Net.string(a)
            if !exclude.contains(s) { out.append(s) }
            a &-= 1
        }
        return out
    }
}

/// Small read-only network queries (no root).
enum Net {
    static func address(_ iface: String) -> String? { ipconfig(["getifaddr", iface]) }
    static func router(_ iface: String) -> String? { ipconfig(["getoption", iface, "router"]) }
    static func mask(_ iface: String) -> String? { ipconfig(["getoption", iface, "subnet_mask"]) }
    static func usable(_ iface: String) -> Bool { address(iface) != nil && router(iface) != nil }

    /// Network identity = router IP + its MAC (two homes with 192.168.1.1 stay distinct).
    /// No ARP entry yet (fresh link) → one ping on that interface fills it (gate-3 final #5).
    /// The MAC comes from the root helper (`netinfo`): macOS Local Network privacy hides the ARP table
    /// from the app itself (unsigned builds lose the permission on every update).
    static func signature(router: String, iface: String) -> String? {
        let out = shell("/usr/bin/sudo", ["-n", NetHelper.helperPath, "netinfo", iface])
        var kv: [String: String] = [:]
        for line in out.split(separator: "\n") {
            let p = line.split(separator: "=", maxSplits: 1).map(String.init)
            if p.count == 2 { kv[p[0]] = p[1] }
        }
        guard kv["GW"] == router, let mac = kv["MAC"], mac.filter({ $0 == ":" }).count == 5 else { return nil }
        return "\(router)@\(mac)"
    }

    /// Any local-network packet from the app triggers macOS's one-time Local Network prompt.
    static func requestLocalNetworkAccess(_ router: String) {
        guard !asked else { return }
        asked = true
        let c = NWConnection(host: NWEndpoint.Host(router), port: 9, using: .udp)   // discard port
        c.start(queue: .global())
        c.send(content: Data([0]), completion: .contentProcessed { _ in c.cancel() })
    }
    private static var asked = false

    static func int(_ s: String) -> UInt32? {
        let p = s.split(separator: ".").compactMap { UInt32($0) }
        guard p.count == 4, p.allSatisfy({ $0 <= 255 }) else { return nil }
        return p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]
    }
    static func string(_ v: UInt32) -> String { "\(v >> 24 & 255).\(v >> 16 & 255).\(v >> 8 & 255).\(v & 255)" }

    private static func ipconfig(_ args: [String]) -> String? {
        let s = shell("/usr/sbin/ipconfig", args).trimmingCharacters(in: .whitespacesAndNewlines)
        return int(s) == nil ? nil : s
    }

    private static func shell(_ path: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }
}
