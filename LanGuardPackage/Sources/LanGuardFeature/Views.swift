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
            Button {
                model.protection.panic()
            } label: {
                Label("Restore Normal Networking (Panic)", systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
            }
            if NetHelper.panicked {
                Button("Re-Enable Connection Protection") { model.protection.rearm() }
            }
            Divider()
        }

        Text(model.statusLine)
        Text("Protection: \(model.protection.status)")
        if let status = model.handover.status { Text(status) }

        Divider()

        if model.handover.switchedToWiFi {
            Button("Back to LAN   \(model.settings.hotKey.label)") { model.backToLAN() }
        } else {
            Button("Switch to Wi-Fi (Safe Unplug)   \(model.settings.hotKey.label)") { model.switchToWiFi() }
                .disabled(!model.engine.wiredUp)
        }

        Toggle("Auto-Toggle Wi-Fi", isOn: Binding(
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
                .accessibilityHidden(true)

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

            Divider()

            VStack(spacing: 8) {
                Text("Have an idea, or want to help build it?").font(.headline)
                Text("Feature requests and pull requests are welcome. Ko-fi supporters go to the front of the queue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Link(destination: URL(string: "https://github.com/roypadina/LanGuard/issues/new?template=feature_request.yml")!) {
                        Text("Request a feature").frame(minWidth: 120)
                    }
                    .buttonStyle(.bordered)

                    Link(destination: URL(string: "https://github.com/roypadina/LanGuard/blob/main/CONTRIBUTING.md")!) {
                        Text("Contribute").frame(minWidth: 90)
                    }
                    .buttonStyle(.bordered)
                }
            }

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
    @State private var tick: Int = 0
    @State private var pane: Pane

    /// Explicit in-window tab bar: on macOS 26+ a native `TabView` moves its tabs into the title-bar
    /// toolbar as icon-only buttons that collapse behind a ">>" overflow — tabs become invisible.
    enum Pane: String, CaseIterable, Identifiable {
        case general = "General", interfaces = "Interfaces", switching = "Switching",
             protection = "Protection", about = "About"
        var id: Self { self }
    }

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    public init(model: AppModel) { self.model = model; _pane = State(initialValue: .general) }

    /// Dev-only (screenshot rendering): open on a given tab.
    init(model: AppModel, pane: Pane) { self.model = model; _pane = State(initialValue: pane) }

    private var wired: [NetInterface] { InterfaceCatalog.wired() }
    private var wifi: [NetInterface] { InterfaceCatalog.wifi() }

    public var body: some View {
        let _ = tick
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
        // Every 2 s the body re-evaluates (helper/login/hot-key state, status texts, link dots);
        // `let _ = tick` ties it to the timer without giving rows a new identity (keeps focus).
        .onReceive(refresh) { _ in tick &+= 1 }
    }

    // MARK: General

    private var general: some View {
        Form {
            Section {
                Toggle("Auto-toggle Wi-Fi", isOn: Binding(
                    get: { model.settings.autoEnabled },
                    set: { model.setAuto($0) }
                ))
                LaunchAtLoginToggle()
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
                empty: "No wired adapters found. Plug in Ethernet or a dock.",
                interfaces: wired,
                isActive: { model.linkActive($0.bsdName) },
                words: ("Link up", "Link down"),
                isOn: { model.settings.wiredEnabled($0) },
                set: { iface, on in
                    model.settings.setWiredEnabled(iface, on)
                    model.selectionChanged()
                }
            )

            section(
                title: "Controlled Wi-Fi",
                subtitle: "These adapters get switched on/off.",
                empty: "No Wi-Fi adapter found.",
                interfaces: wifi,
                isActive: { model.wifiPoweredOn($0.bsdName) },
                words: ("On", "Off"),
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
                            Label {
                                Text("Used by another app. Record another.").foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                            .font(.callout)
                        }
                        Button(recorder.recording ? "Press keys… (Esc cancels)" : model.settings.hotKey.label) {
                            recorder.toggle(current: model.settings.hotKey, save: model.setHotKey)
                        }
                        .accessibilityLabel("Shortcut")
                        .accessibilityValue(recorder.recording ? "Press keys" : model.settings.hotKey.label)
                    }
                }
            } header: {
                Text("Switch to Wi-Fi")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before unplugging the LAN: turns Wi-Fi on, checks it reaches the internet, moves traffic to it (connection protection), then tells you it's safe to unplug. Changed your mind? Press it again (or Back to LAN in the menu) while still plugged in.")
                    Text("Global: works in every app and wins over the same keys inside apps (e.g. cmux). Needs ⌃, ⌥ or ⌘.")
                }
            }

            Section("Notifications") {
                Toggle("Banner when Wi-Fi turns off", isOn: Binding(
                    get: { model.settings.notifyMovedToLAN },
                    set: { model.settings.notifyMovedToLAN = $0 }
                ))
                Toggle("Banner when Wi-Fi turns back on", isOn: Binding(
                    get: { model.settings.notificationsEnabled },
                    set: { model.settings.notificationsEnabled = $0 }
                ))
                Toggle("Progress window while switching", isOn: Binding(
                    get: { model.settings.switchProgressPopup },
                    set: { model.settings.switchProgressPopup = $0 }
                ))
                Toggle("“Safe to unplug” alert", isOn: Binding(
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
                Text("In the menu: Restore Normal Networking (Panic).")
                Text("In Terminal: sudo \(NetHelper.helperPath) panic")
                Text("Without the helper: run `sudo -s`, then paste the one-liner from the README (section “Panic”).")
                Text("Or restart the Mac.")
            }
            .textSelection(.enabled)
        }
    }

    // MARK: About

    private var about: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40).accessibilityHidden(true)
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
        empty: String,
        interfaces: [NetInterface],
        isActive: @escaping (NetInterface) -> Bool,
        words: (active: String, inactive: String),
        isOn: @escaping (NetInterface) -> Bool,
        set: @escaping (NetInterface, Bool) -> Void
    ) -> some View {
        Section {
            if interfaces.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            } else {
                ForEach(interfaces) { iface in
                    let active = isActive(iface) // one read per row: it can shell out to ifconfig
                    Toggle(isOn: Binding(
                        get: { isOn(iface) },
                        set: { set(iface, $0) }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: active ? "circle.fill" : "circle")
                                .foregroundStyle(active ? Color.green : Color.secondary)
                                .imageScale(.small)
                                .accessibilityHidden(true)
                            Text("\(iface.displayName)  (\(iface.bsdName))")
                            Text(active ? words.active : words.inactive)
                                .foregroundStyle(.secondary)
                            if iface.isVirtual {
                                Text("virtual")
                                    .font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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

/// Records one key combo for the global shortcut. Shared object, not view-local state, so recording
/// survives the Settings view being rebuilt.
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
            p.title = "Switch to Wi-Fi"
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
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .onChange(of: handover.status) { _, status in
            if let status { AccessibilityNotification.Announcement(status).post() } // VoiceOver: progress is otherwise silent
        }
    }
}
