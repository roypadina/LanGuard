import AppKit
import LanGuardFeature
import Sparkle

/// Sparkle updater: feed URL + public key come from Info.plist.
@MainActor enum Updates {
    static let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: presenter, userDriverDelegate: presenter)
    static func check() { controller.checkForUpdates(nil) }
    /// Version of an update Sparkle found that is not installed yet; nil when none is known.
    private(set) static var availableVersion: String? {
        didSet { AppModel.shared.objectWillChange.send() }  // re-render the menu: its SwiftUI body won't re-run on its own
    }
    /// Title for the status-item menu: offers a found update, else a manual check.
    static var menuTitle: String { availableVersion.map { "Install Update \($0)…" } ?? "Check for Updates…" }
    private static let presenter = Presenter()

    /// Remembers a found update for the menu, and gives the menu-bar-only app a Dock icon + front
    /// window while an update alert is up (it would open behind other windows otherwise).
    private final class Presenter: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
        // Sparkle calls these on the main thread; its header just doesn't say so to Swift.
        func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
            let version = item.displayVersionString
            MainActor.assumeIsolated { Updates.availableVersion = version }
        }

        func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
            MainActor.assumeIsolated { Updates.availableVersion = nil }
        }

        var supportsGentleScheduledUpdateReminders: Bool { true }

        func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
            MainActor.assumeIsolated {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
            }
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
