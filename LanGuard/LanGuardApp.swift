import SwiftUI
import LanGuardFeature
import Sparkle

/// Sparkle updater: feed URL + public key come from Config/Info.plist.
@MainActor enum Updates {
    static let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: presenter)
    static func check() { controller.checkForUpdates(nil) }
    private static let presenter = Presenter()

    /// A menu-bar-only app's scheduled update alert opens behind other windows, with no Dock icon to
    /// find it by. Same rule as `AccessoryWindows`: Dock icon + front while the alert is up, then back.
    private final class Presenter: NSObject, SPUStandardUserDriverDelegate {
        var supportsGentleScheduledUpdateReminders: Bool { true }

        func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }

        func standardUserDriverWillFinishUpdateSession() {
            DispatchQueue.main.async {  // after Sparkle's window has closed
                if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
        MenuContent.checkForUpdates = Updates.check  // Sparkle lives in the app target, the menu in the package
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
