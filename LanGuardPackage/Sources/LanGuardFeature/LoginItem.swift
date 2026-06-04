import Foundation
import ServiceManagement

/// Wraps the "start at login" login-item registration.
public enum LoginItem {

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
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
