import ServiceManagement
import SwiftUI

/// First-launch welcome (MBX-18): why LanGuard exists, where the icon is, how to get back in without
/// the icon (MBX-8, MBX-9), and the login item (MBX-17). Shown once from AppDelegate; re-opened from
/// Settings > About.
@MainActor
public enum WelcomeWindow {
    private static var window: NSWindow?

    public static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView(
                model: .shared,
                onOpenSettings: { window?.close(); SettingsWindow.shared.show() },
                onDone: { window?.close() })))
            w.title = "Welcome"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        if let window { AccessoryWindows.shared.show(window) }
    }
}

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    let onOpenSettings: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to LanGuard").font(.title2.bold())
                    Text("macOS keeps Wi-Fi on while you are docked on Ethernet, so traffic can leave by the wrong network. LanGuard turns Wi-Fi off when the cable is in and back on when you unplug.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            row("cable.connector", "LanGuard lives in the menu bar.",
                "Its icon shows LAN or Wi-Fi, whichever you are on. Click it to switch, pause auto-toggle or open Settings.")
            row("wifi", "Wi-Fi follows your cable.",
                "Wi-Fi turns off once the wired link reaches the internet and comes back on when you unplug. Turn Wi-Fi on by hand and it stays on until the next unplug.")
            row("lock.shield", "Switch to Wi-Fi before you unplug.",
                "Press \(model.settings.hotKey.label) or choose Switch to Wi-Fi in the menu, so Wi-Fi is up before the cable goes. With connection protection on (Settings > Protection, admin password once), open connections survive too.")
            row("questionmark.circle", "Icon missing?",
                "Open LanGuard again from Applications to get Settings, or check System Settings > Menu Bar.")
            LaunchAtLoginToggle()
            SupportBox()
            HStack {
                Button("Open Settings", action: onOpenSettings)
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Quiet Ko-fi support box shared by every Padina app's welcome window. Never `.borderedProminent`:
/// the app's own next step stays the primary action.
struct SupportBox: View {
    var body: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Free and open source").font(.headline)
                    Text("If LanGuard saves you time, a coffee on Ko-fi keeps the next one coming.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Link("Support on Ko-fi ☕", destination: AboutInfo.koFi).buttonStyle(.bordered)
            }
            .padding(4)
        }
    }
}

/// Settings > General and the welcome window (MBX-17): user action only, status re-read on activation.
struct LaunchAtLoginToggle: View {
    @State private var status = LoginItem.status

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Open at Login", isOn: Binding(
                get: { status == .enabled },
                set: { on in
                    LoginItem.setEnabled(on)  // keeps the registeredBundlePath self-heal in sync
                    status = LoginItem.status
                }))
            if status == .requiresApproval {
                Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            } else if status == .notFound {
                Text("Move LanGuard to Applications to open it at login.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = LoginItem.status  // the user may change it in System Settings
        }
    }
}
