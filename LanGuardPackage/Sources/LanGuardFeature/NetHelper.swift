import Foundation
import AppKit

/// The root side of connection protection: the `languard-net` helper script, its LaunchDaemon
/// guardian (`check` every 3 s) and a sudoers rule that allows only that one helper path.
/// All installed with one admin prompt; see Resources/languard-net.sh for the safety contract.
public enum NetHelper {

    public static let helperPath = "/Library/PrivilegedHelperTools/languard-net"
    static let plistPath = "/Library/LaunchDaemons/com.roypadina.languard-net.plist"
    static let label = "com.roypadina.languard-net"
    public static let sudoersFile = "/etc/sudoers.d/languard"
    static let statePath = "/var/run/languard-net.state"
    static let panicPath = "/var/run/languard-net.panic"
    static let tickPath = "/var/run/languard-net.tick"
    static let reasonPath = "/var/run/languard-net.reason"

    /// Helper exit codes (mirror languard-net.sh).
    enum Exit: Int32 { case ok = 0, badArgs = 2, conflict = 3, panicked = 4, otherInstance = 5, taken = 6, verifyFailed = 7, noState = 8, noGuardian = 9 }

    /// Panic without the helper: the helper's `down`, inlined. Removes only en* /1 routes and
    /// en* /32 aliases that are not the DHCP address. Also printed in Settings/README.
    public static let panicOneLiner = #"for n in 0.0.0.0/1 128.0.0.0/1; do i=$(route -n get -net $n 2>/dev/null | awk '$1=="interface:"{print $2}'); case $i in en[0-9]*) route -q -n delete -net $n;; esac; done; for i in $(ifconfig -l | tr ' ' '\n' | grep -E '^en[0-9]+$'); do p=$(ipconfig getifaddr $i); ifconfig $i | awk '/inet .* netmask 0xffffffff/{print $2}' | while read a; do [ "$a" != "$p" ] && ifconfig $i inet $a -alias; done; done; rm -f /var/run/languard-net.state; touch /var/run/languard-net.panic"#

    private static var bundledScript: URL? { Bundle.module.url(forResource: "languard-net", withExtension: "sh") }
    private static var bundledPlist: URL? { Bundle.module.url(forResource: "com.roypadina.languard-net", withExtension: "plist") }

    public static var installed: Bool {
        [helperPath, plistPath, sudoersFile].allSatisfy { FileManager.default.fileExists(atPath: $0) }
    }

    /// Installed helper differs from the one bundled with this build → reinstall needed.
    public static var outdated: Bool {
        guard installed, let url = bundledScript else { return false }
        return FileManager.default.contents(atPath: helperPath) != (try? Data(contentsOf: url))
    }

    public static var panicked: Bool { FileManager.default.fileExists(atPath: panicPath) }

    /// The guardian LaunchDaemon proves it runs by stamping a tick on every `check` (≈ every 3 s).
    /// No fresh tick = no guardian = protection must not be armed (gate-2 blocker #2).
    public static var guardianRunning: Bool {
        guard let t = (try? String(contentsOfFile: tickPath, encoding: .utf8))
                .flatMap({ TimeInterval($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { return false }
        return Date().timeIntervalSince1970 - t <= 15
    }

    /// Why the guardian last tore protection down (bad-state | iface-gone | link | network | vpn | unhealthy).
    static var teardownReason: String? {
        (try? String(contentsOfFile: reasonPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Current helper state (A, IFACE, GW, PID) or nil when protection is not set up.
    static func state() -> [String: String]? {
        guard let text = try? String(contentsOfFile: statePath, encoding: .utf8) else { return nil }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { out[parts[0]] = parts[1] }
        }
        return out["A"] == nil ? nil : out
    }

    /// One admin prompt: install helper (root:wheel 0755), guardian LaunchDaemon and the sudoers
    /// rule (validated with visudo; replaces the old networksetup rule in the same file).
    @discardableResult
    public static func install() -> Bool {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
              let script = bundledScript?.path, let plist = bundledPlist?.path,
              !script.contains("'"), !plist.contains("'") else { return false }
        let rule = "\(user) ALL=(root) NOPASSWD: \(helperPath)"
        let ok = admin("""
            set -e; mkdir -p /Library/PrivilegedHelperTools; \
            /usr/bin/install -m 755 -o root -g wheel '\(script)' \(helperPath); \
            /usr/bin/install -m 644 -o root -g wheel '\(plist)' \(plistPath); \
            f=$(mktemp); echo '\(rule)' > "$f"; /usr/sbin/visudo -cf "$f"; \
            /usr/bin/install -m 440 -o root -g wheel "$f" \(sudoersFile); rm -f "$f"; \
            /bin/launchctl bootout system/\(label) 2>/dev/null || true; \
            /bin/launchctl bootstrap system \(plistPath)
            """)
        Log.write("NetHelper.install ok=\(ok)")
        return ok
    }

    /// Remove everything (runs `down` first so nothing is left in the routing table).
    @discardableResult
    public static func remove() -> Bool {
        let ok = admin("""
            \(helperPath) down 2>/dev/null || true; \
            /bin/launchctl bootout system/\(label) 2>/dev/null || true; \
            rm -f \(plistPath) \(helperPath) \(sudoersFile) /var/run/languard-net.lock
            """)
        Log.write("NetHelper.remove ok=\(ok)")
        return ok
    }

    /// Run a helper verb via `sudo -n`. Blocking (up/move take ~1 s) — call off the main thread.
    @discardableResult
    static func run(_ args: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", helperPath] + args
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do { try proc.run() } catch { return -1 }
        proc.waitUntilExit()
        Log.write("languard-net \(args.joined(separator: " ")) → \(proc.terminationStatus)")
        return proc.terminationStatus
    }

    /// PANIC: restore normal networking. sudo → admin prompt → inline one-liner (no helper needed).
    /// Safe to call from any thread, concurrently with anything (helper `panic` is idempotent).
    /// Call from a background queue (never main): the admin fallback runs on main and is awaited.
    @discardableResult
    public static func panic() -> Bool {
        if FileManager.default.fileExists(atPath: helperPath), run(["panic"]) == 0 { return true }
        // Fallback admin prompt: NSAppleScript is main-thread only (gate-3 #12).
        let cmd = FileManager.default.fileExists(atPath: helperPath) ? "\(helperPath) panic" : panicOneLiner
        let ok = Thread.isMainThread ? admin(cmd) : DispatchQueue.main.sync { admin(cmd) }
        Log.write("NetHelper.panic via admin ok=\(ok)")
        return ok
    }

    /// Run a shell command as root via the standard macOS admin prompt.
    private static func admin(_ shell: String) -> Bool {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?
            .executeAndReturnError(&error)
        if let error { Log.write("admin command failed: \(error)") }
        return error == nil
    }
}
