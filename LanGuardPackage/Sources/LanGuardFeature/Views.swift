import SwiftUI
import AppKit

// MARK: - Menu bar dropdown

public struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        // Always first and always enabled while the helper exists: one click back to normal networking.
        if NetHelper.installed || NetHelper.state() != nil {
            Button("⚠︎ Restore normal networking (panic)") { model.protection.panic() }
            if NetHelper.panicked {
                Button("Re-enable connection protection") { model.protection.rearm() }
            }
            Divider()
        }

        Text(model.statusLine)
        Text("Protection: \(model.protection.status)")
        if let status = model.handover.status { Text(status) }

        Divider()

        Button("Switch to Wi-Fi (safe unplug)   \(model.settings.hotKey.label)") { model.switchToWiFi() }
            .disabled(!model.engine.wiredUp)

        Toggle("Auto-toggle Wi-Fi", isOn: Binding(
            get: { model.settings.autoEnabled },
            set: { model.setAuto($0) }
        ))

        Button("Settings…") {
            openWindow(id: "config")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("About LanGuard") {
            AboutWindow.show()
        }

        Button("Support on Ko-fi ☕") { NSWorkspace.shared.open(AboutInfo.koFi) }

        Divider()

        Button("Quit LanGuard") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

// MARK: - About

enum AboutInfo {
    static let koFi = URL(string: "https://ko-fi.com/roypadina")!
    static let github = URL(string: "https://github.com/roypadina/LanGuard")!
    static let issues = URL(string: "https://github.com/roypadina/LanGuard/issues")!
    static let version = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"
}

/// Custom About window (the standard panel's fixed-height credits box clips text).
@MainActor
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            w.title = "About LanGuard"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    private let info = Bundle.main.infoDictionary ?? [:]

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 2) {
                Text("LanGuard").font(.title.bold())
                Text("Version \(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text("Made by Roy Padina").font(.headline)
                Text("I'm a software engineer from Israel who builds small, focused Mac tools to fix the little annoyances in my own day — then shares them free and open source.")
                Text("If this app saves you time, a coffee on Ko-fi keeps the next one coming. ☕")
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Link(destination: AboutInfo.koFi) {
                    Text("Support on Ko-fi ☕").frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Link(destination: AboutInfo.github) {
                    Text("GitHub").frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Link("Report an issue", destination: AboutInfo.issues)
                .font(.callout)

            Text("© Roy Padina · MIT")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 380)
    }
}

// MARK: - Settings window

public struct ConfigView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var recorder = ShortcutRecorder.shared
    @State private var loginOn: Bool = LoginItem.isEnabled
    @State private var tick: Int = 0
    @State private var pane: Pane = .general

    /// Explicit in-window tab bar: on macOS 26+ a native `TabView` moves its tabs into the title-bar
    /// toolbar as icon-only buttons that collapse behind a ">>" overflow — tabs become invisible.
    private enum Pane: String, CaseIterable, Identifiable {
        case general = "General", interfaces = "Interfaces", switching = "Switching",
             protection = "Protection", about = "About"
        var id: Self { self }
    }

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    public init(model: AppModel) { self.model = model }

    private var wired: [NetInterface] { InterfaceCatalog.wired() }
    private var wifi: [NetInterface] { InterfaceCatalog.wifi() }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Group {
                switch pane {
                case .general: general
                case .interfaces: interfaces
                case .switching: switching
                case .protection: protection
                case .about: about
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 500)
        // Every 2 s the body re-evaluates (helper/login/hot-key state, status texts); the interface
        // rows and the protection status row also carry `.id(tick)` so they are rebuilt, not diffed.
        .onReceive(refresh) { _ in tick &+= 1 }
        .onAppear { loginOn = LoginItem.isEnabled }
    }

    // MARK: General

    private var general: some View {
        Form {
            Section {
                Toggle("Auto-toggle enabled", isOn: Binding(
                    get: { model.settings.autoEnabled },
                    set: { model.setAuto($0) }
                ))
                Toggle("Start at login", isOn: $loginOn)
                    .onChange(of: loginOn) { _, newValue in
                        LoginItem.setEnabled(newValue)
                        if newValue { LoginItem.promptForApprovalIfNeeded() }
                        loginOn = LoginItem.isEnabled
                    }
            } footer: {
                Text("Login item: \(LoginItem.statusDescription)")
                    .foregroundStyle(LoginItem.status == .requiresApproval ? Color.orange : .secondary)
            }

            Section {
                Picker("Menu bar icon", selection: Binding(
                    get: { model.settings.menuIconStyle },
                    set: { model.settings.menuIconStyle = $0 }
                )) {
                    ForEach(MenuIconStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: Interfaces

    private var interfaces: some View {
        Form {
            section(
                title: "Wired triggers",
                subtitle: "Wi-Fi turns off when any checked wired link is active. Virtual adapters (bridge/VPN/VM) are off by default.",
                interfaces: wired,
                isActive: { model.linkActive($0.bsdName) },
                isOn: { model.settings.wiredEnabled($0) },
                set: { iface, on in
                    model.settings.setWiredEnabled(iface, on)
                    model.selectionChanged()
                }
            )

            section(
                title: "Controlled Wi-Fi",
                subtitle: "These adapters get switched on/off.",
                interfaces: wifi,
                isActive: { model.wifiPoweredOn($0.bsdName) },
                isOn: { model.settings.wifiEnabled($0.bsdName) },
                set: { iface, on in
                    model.settings.setWiFiEnabled(iface.bsdName, on)
                    model.selectionChanged()
                }
            )
        }
    }

    // MARK: Switching

    private var switching: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    HStack {
                        if HotKey.inUse {
                            Text("Used by another app — record another").font(.caption).foregroundStyle(.orange)
                        }
                        Button(recorder.recording ? "Press keys… (Esc cancels)" : model.settings.hotKey.label) {
                            recorder.toggle(current: model.settings.hotKey, save: model.setHotKey)
                        }
                    }
                }
            } header: {
                Text("Switch to Wi-Fi")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before unplugging the LAN: turns Wi-Fi on, checks it reaches the internet, moves traffic to it (connection protection), then tells you it's safe to unplug.")
                    Text("Global: works in every app and wins over the same keys inside apps (e.g. cmux). Needs ⌃, ⌥ or ⌘.")
                }
            }

            Section("Notifications") {
                Toggle("LAN connected: \"Wi-Fi off, traffic on LAN\" banner", isOn: Binding(
                    get: { model.settings.notifyMovedToLAN },
                    set: { model.settings.notifyMovedToLAN = $0 }
                ))
                Toggle("LAN unplugged: \"Wi-Fi back on\" banner", isOn: Binding(
                    get: { model.settings.notificationsEnabled },
                    set: { model.settings.notificationsEnabled = $0 }
                ))
                Toggle("Switch to Wi-Fi: progress window (closes itself when ready)", isOn: Binding(
                    get: { model.settings.switchProgressPopup },
                    set: { model.settings.switchProgressPopup = $0 }
                ))
                Toggle("Switch to Wi-Fi: \"Safe to unplug LAN\" popup", isOn: Binding(
                    get: { model.settings.safeToUnplugPopup },
                    set: { model.settings.safeToUnplugPopup = $0 }
                ))
            }
        }
    }

    // MARK: Protection

    private var protection: some View {
        Form {
            Section {
                if NetHelper.installed {
                    Toggle("Protect connections", isOn: Binding(
                        get: { model.settings.protectionEnabled },
                        set: { model.setProtection($0) }
                    ))
                    if let net = model.protection.currentNetwork {
                        Toggle("Protect this network (\(net.split(separator: "@").first ?? ""))", isOn: Binding(
                            get: { model.settings.protectedNetworks.contains(net) },
                            set: { model.setProtectThisNetwork($0) }
                        ))
                    }
                    LabeledContent("Status", value: model.protection.status)
                        .id(tick) // force status refresh
                    HStack {
                        if NetHelper.outdated {
                            Button("Update helper…") { NetHelper.install() }
                        }
                        Button("Uninstall helper…") { model.setProtection(false); NetHelper.remove() }
                    }
                } else {
                    Button("Install helper… (admin password once)") { NetHelper.install() }
                }
            } header: {
                Text("Connection protection")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keeps connections (agents, VPNs, downloads) alive when you plug or unplug the LAN: traffic uses a stable address that moves between LAN and Wi-Fi. Only on networks where LAN and Wi-Fi share a router. IPv4 only. Not for full-tunnel VPNs (\"send all traffic\") — split-tunnel VPNs like Pritunl and Tailscale are fine.")
                    Text("Installs a root helper (\(NetHelper.helperPath)), a guardian that removes everything if the network looks wrong, and a sudo rule for that helper only.")
                }
            }

            Section("Panic") {
                Text("Menu → \"Restore normal networking\", the Raycast script \"LanGuard Panic\", or reboot. Without LanGuard: in Terminal run `sudo -s`, then paste the one-liner from the README (section \"Panic\").")
            }
        }
    }

    // MARK: About

    private var about: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                    VStack(alignment: .leading) {
                        Text("LanGuard").font(.headline)
                        Text("Version \(AboutInfo.version)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("About LanGuard…") { AboutWindow.show() }
                    Button("Support on Ko-fi ☕") { NSWorkspace.shared.open(AboutInfo.koFi) }
                        .buttonStyle(.borderedProminent)
                }
            }

            Section {
                Toggle("Enable debug logging", isOn: Binding(
                    get: { model.settings.debugLoggingEnabled },
                    set: {
                        model.settings.debugLoggingEnabled = $0
                        if $0 { Log.write("--- debug logging enabled from Settings ---") }
                    }
                ))
                HStack {
                    Button("Reveal Logs in Finder") { Log.revealInFinder() }
                    Button("Clear Logs") { Log.clear() }
                }
            } header: {
                Text("Debug")
            } footer: {
                Text("Writes a log to ~/Library/Logs/LanGuard. Turn this on, reproduce the issue, then send us the log file.")
            }
        }
    }

    @ViewBuilder
    private func section(
        title: String,
        subtitle: String,
        interfaces: [NetInterface],
        isActive: @escaping (NetInterface) -> Bool,
        isOn: @escaping (NetInterface) -> Bool,
        set: @escaping (NetInterface, Bool) -> Void
    ) -> some View {
        Section {
            if interfaces.isEmpty {
                Text("No interfaces found.").foregroundStyle(.secondary)
            } else {
                ForEach(interfaces) { iface in
                    Toggle(isOn: Binding(
                        get: { isOn(iface) },
                        set: { set(iface, $0) }
                    )) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isActive(iface) ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text("\(iface.displayName)  (\(iface.bsdName))")
                            if iface.isVirtual {
                                Text("virtual")
                                    .font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .id("\(iface.id)-\(tick)") // unique per row; tick forces the status-dot refresh
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(subtitle)
        }
    }
}

// MARK: - Switch to Wi-Fi: shortcut recorder + progress window

/// Records one key combo for the global shortcut. Shared object, because the Settings view is
/// rebuilt every 2 s (`.id(tick)`), which would drop view-local recording state.
final class ShortcutRecorder: ObservableObject {
    static let shared = ShortcutRecorder()
    @Published private(set) var recording = false
    private var monitor: Any?

    func toggle(current: HotKeyCombo, save: @escaping (HotKeyCombo) -> Void) {
        if recording { finish(); HotKey.register(current); return }
        HotKey.unregister() // so pressing the current combo records it instead of firing it
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.finish(); HotKey.register(current); return nil } // Esc
            guard let combo = HotKeyCombo(keyCode: event.keyCode, flags: event.modifierFlags,
                                          characters: event.charactersIgnoringModifiers) else {
                NSSound.beep() // needs ⌃, ⌥ or ⌘
                return nil
            }
            self.finish()
            save(combo)
            return nil
        }
    }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

/// Floating, closeable progress window for Switch to Wi-Fi. Closing it doesn't stop the switch;
/// the hand-over closes it itself when it's safe to unplug.
@MainActor
enum ProgressPanel {
    private static var panel: NSPanel?

    static func show(_ handover: Handover) {
        if panel == nil {
            let p = NSPanel(contentViewController: NSHostingController(rootView: SwitchProgressView(handover: handover)))
            p.title = "LanGuard"
            p.styleMask = [.titled, .closable, .utilityWindow]
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            panel = p
        }
        panel?.center()
        panel?.orderFrontRegardless()
    }

    static func close() { panel?.orderOut(nil) }
}

struct SwitchProgressView: View {
    @ObservedObject var handover: Handover

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Switching to Wi-Fi").font(.headline)
            }
            Text(handover.status ?? "Done").font(.callout)
            Text("Keep the LAN cable plugged in. This window closes itself when it's safe to unplug.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}
