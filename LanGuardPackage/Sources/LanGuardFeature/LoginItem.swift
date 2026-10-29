import Foundation
import ServiceManagement

/// What registration action a launch needs, given current state.
public enum LoginRegisterDecision: Equatable {
    case none             // already registered for this path — nothing to do
    case register         // registration lost after it was on — register again
    case reRegisterMoved  // registration lost or bundle moved — re-register
}

/// Wraps the "Open at Login" login-item registration. Self-heals: re-registers
/// automatically when the app bundle moves or the registration is lost. Never opts
/// the user in on its own: `LaunchAtLoginToggle` (Welcome, Settings) is the opt-in.
public enum LoginItem {

    private static let pathKey = "registeredBundlePath"

    public static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Pure decision used by `ensureRegistered` (unit-tested). A `nil` stored path
    /// while already enabled means "first time we're recording it" → no re-register.
    /// A `nil` stored path while not registered means the user never turned it on (or turned
    /// it off: `setEnabled(false)` clears the path) → stay off.
    public static func decide(status: SMAppService.Status,
                              storedPath: String?,
                              currentPath: String) -> LoginRegisterDecision {
        switch status {
        case .notRegistered:
            return storedPath != nil ? .register : .none
        case .notFound:
            return .reRegisterMoved
        case .enabled, .requiresApproval:
            return (storedPath == currentPath || storedPath == nil) ? .none : .reRegisterMoved
        @unknown default:
            return .none
        }
    }

    /// Ensure the login item is registered for the CURRENT bundle path.
    /// Re-registers if the app moved or the registration was lost; does nothing for a
    /// login item the user never enabled. Returns the action taken so the caller can log it.
    @discardableResult
    public static func ensureRegistered() -> LoginRegisterDecision {
        let current = Bundle.main.bundlePath
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: pathKey)
        let decision = decide(status: status, storedPath: stored, currentPath: current)

        switch decision {
        case .none:
            // Already enabled but unrecorded → adopt current path silently so a
            // genuine future move is detected.
            if status == .enabled, stored != current {
                defaults.set(current, forKey: pathKey)
            }
            return .none

        case .register, .reRegisterMoved:
            if decision == .reRegisterMoved {
                try? SMAppService.mainApp.unregister()
            }
            do {
                try SMAppService.mainApp.register()
                defaults.set(current, forKey: pathKey)
            } catch {
                NSLog("LanGuard: login item register failed: \(error)")
            }
            return decision
        }
    }

    /// Manual toggle from `LaunchAtLoginToggle`.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        let defaults = UserDefaults.standard
        do {
            if enabled {
                try SMAppService.mainApp.register()
                defaults.set(Bundle.main.bundlePath, forKey: pathKey)
            } else {
                try SMAppService.mainApp.unregister()
                defaults.removeObject(forKey: pathKey)
            }
            return true
        } catch {
            NSLog("LanGuard: login item \(enabled ? "register" : "unregister") failed: \(error)")
            return false
        }
    }
}

/// Removes the legacy shell-based com.roy.wifitoggle LaunchAgent so it doesn't
/// fight the app. Runs once.
public enum LegacyCleanup {

    public static func run() {
        let home = NSHomeDirectory()
        let plist = "\(home)/Library/LaunchAgents/com.roy.wifitoggle.plist"
        let fm = FileManager.default
        guard fm.fileExists(atPath: plist) else { return }

        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "gui/\(getuid())/com.roy.wifitoggle"]
        try? bootout.run()
        bootout.waitUntilExit()

        try? fm.removeItem(atPath: plist)
        try? fm.removeItem(atPath: "\(home)/bin/wifi-toggle.sh")
        NSLog("LanGuard: removed legacy com.roy.wifitoggle LaunchAgent")
    }
}
