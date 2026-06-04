import SwiftUI
import LanGuardFeature

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
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
            Image(systemName: model.menuSymbol)
        }
        .menuBarExtraStyle(.menu)

        Window("LanGuard Settings", id: "config") {
            ConfigView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
