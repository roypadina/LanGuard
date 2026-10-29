import AppKit
import SwiftUI

/// Real windows from a menu-bar-only app (MBX-15): Dock icon and menu bar while one is open, back to
/// `.accessory` when the last one closes. Alert panels can't become main, so they don't count.
@MainActor
final class AccessoryWindows: NSObject, NSWindowDelegate {
    static let shared = AccessoryWindows()

    func show(_ window: NSWindow) {
        window.delegate = self
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.canBecomeMain }
        if !others { NSApp.setActivationPolicy(.accessory) }
    }
}

/// Own Settings window (MBX-16): `SettingsLink`/`openSettings` are unreliable in a menu-bar-only app.
/// `NSTabViewController` keeps the tabs as toolbar icons; a SwiftUI `TabView` in a plain `NSWindow`
/// would draw in-window tabs instead.
@MainActor
public final class SettingsWindow {
    public static let shared = SettingsWindow()
    private var window: NSWindow?

    public func show() {
        if window == nil {
            let tabs = SettingsTabs()
            tabs.tabStyle = .toolbar
            // Each pane gets its own height (SET-8): grouped forms have no intrinsic height. Measured offscreen
            // (scroll content): General ~180, Interfaces ~190 + 37 per adapter (6 fit, then it scrolls),
            // Switching ~420, Protection ~540 with the helper installed, About ~320.
            add(tabs, .general, "gearshape", height: 220)
            add(tabs, .interfaces, "cable.connector", height: 420)
            add(tabs, .switching, "arrow.left.arrow.right", height: 440)
            add(tabs, .protection, "lock.shield", height: 560)
            add(tabs, .about, "info.circle", height: 320)
            if let last = UserDefaults.standard.string(forKey: SettingsTabs.lastTabKey),  // reopen on the last pane (SET-3)
               let index = tabs.tabViewItems.firstIndex(where: { $0.label == last }) {
                tabs.selectedTabViewItemIndex = index
            }
            let w = NSWindow(contentViewController: tabs)
            w.styleMask = [.titled, .closable, .miniaturizable]  // keep .miniaturizable so the button dims, not vanishes
            w.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label
            w.isReleasedWhenClosed = false
            w.standardWindowButton(.miniaturizeButton)?.isEnabled = false
            w.standardWindowButton(.zoomButton)?.isEnabled = false
            w.center()
            w.setFrameAutosaveName("SettingsWindow")
            window = w
        }
        if let window { AccessoryWindows.shared.show(window) }
    }

    private func add(_ tabs: NSTabViewController, _ pane: ConfigView.Pane, _ symbol: String, height: CGFloat) {
        let host = NSHostingController(rootView: ConfigView(model: .shared, pane: pane).frame(width: 520, height: height))
        host.sizingOptions = .preferredContentSize  // the window follows the selected pane
        host.title = pane.rawValue
        let item = NSTabViewItem(viewController: host)
        item.label = pane.rawValue
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: pane.rawValue)
        tabs.addTabViewItem(item)
    }
}

/// Title follows the selected pane (SET-2); the pane is remembered for the next open (SET-3).
final class SettingsTabs: NSTabViewController {
    static let lastTabKey = "settingsTab"

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let label = tabViewItem?.label else { return }
        view.window?.title = label
        UserDefaults.standard.set(label, forKey: Self.lastTabKey)
    }
}
