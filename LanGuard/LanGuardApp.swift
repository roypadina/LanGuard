import SwiftUI
import LanGuardFeature
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
        AboutInfo.updateMenuTitle = { Updates.menuTitle }
        AboutInfo.checkForUpdates = Updates.check  // Sparkle lives in the app target, the About views in the package
        _ = Updates.controller  // starts the daily update check
        // First launch only (MBX-18); never in the UI-test pipeline.
        guard ProcessInfo.processInfo.environment["LANGUARD_TEST"] != "1",
              !UserDefaults.standard.bool(forKey: "didShowWelcome") else { return }
        UserDefaults.standard.set(true, forKey: "didShowWelcome")
        WelcomeWindow.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Opening LanGuard again (Finder, Raycast) shows Settings: the way in when the icon is hidden (MBX-8).
    @MainActor func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindow.shared.show() }
        return true
    }
}

@main
struct LanGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
        .commands {  // App menu while a window is open (policy .regular)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updates.check() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindow.shared.show() }.keyboardShortcut(",")
            }
        }
    }
}
