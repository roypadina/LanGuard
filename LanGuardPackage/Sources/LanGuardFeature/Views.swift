import SwiftUI
import AppKit

// MARK: - Menu bar dropdown

public struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        Text(model.statusLine)

        Divider()

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
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [.credits: AboutInfo.credits])
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
    static let blurb = "I'm a software engineer from Israel who builds small, focused Mac tools to fix the little annoyances in my own day — then shares them free and open source."
    static let ask = "If this app saves you time, a coffee on Ko-fi keeps the next one coming. ☕"

    static var credits: NSAttributedString {
        let s = NSMutableAttributedString(
            string: "Made by Roy Padina\n\n\(blurb)\n\n\(ask)\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        s.addAttribute(.link, value: koFi, range: (s.string as NSString).range(of: "Ko-fi"))
        return s
    }
}

// MARK: - Settings window

public struct ConfigView: View {
    @ObservedObject var model: AppModel
    @State private var loginOn: Bool = LoginItem.isEnabled
    @State private var tick: Int = 0

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    public init(model: AppModel) { self.model = model }

    private var wired: [NetInterface] { InterfaceCatalog.wired() }
    private var wifi: [NetInterface] { InterfaceCatalog.wifi() }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Toggle("Auto-toggle enabled", isOn: Binding(
                get: { model.settings.autoEnabled },
                set: { model.setAuto($0) }
            ))
            .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Start at login", isOn: $loginOn)
                    .onChange(of: loginOn) { _, newValue in
                        LoginItem.setEnabled(newValue)
                        if newValue { LoginItem.promptForApprovalIfNeeded() }
                        loginOn = LoginItem.isEnabled
                    }
                Text("Login item: \(LoginItem.statusDescription)")
                    .font(.caption)
                    .foregroundStyle(LoginItem.status == .requiresApproval ? Color.orange : .secondary)
            }

            Toggle("Show notifications when Wi-Fi toggles", isOn: Binding(
                get: { model.settings.notificationsEnabled },
                set: { model.settings.notificationsEnabled = $0 }
            ))

            Picker("Menu bar icon", selection: Binding(
                get: { model.settings.menuIconStyle },
                set: { model.settings.menuIconStyle = $0 }
            )) {
                ForEach(MenuIconStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Divider()

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

            Divider()

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

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Debug").font(.headline)
                Toggle("Enable debug logging", isOn: Binding(
                    get: { model.settings.debugLoggingEnabled },
                    set: {
                        model.settings.debugLoggingEnabled = $0
                        if $0 { Log.write("--- debug logging enabled from Settings ---") }
                    }
                ))
                Text("Writes a log to ~/Library/Logs/LanGuard. Turn this on, reproduce the issue, then send us the log file.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Reveal Logs in Finder") { Log.revealInFinder() }
                    Button("Clear Logs") { Log.clear() }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                    VStack(alignment: .leading) {
                        Text("About LanGuard").font(.headline)
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Made by Roy Padina").font(.subheadline.bold())
                Text(AboutInfo.blurb).font(.caption).foregroundStyle(.secondary)
                Text(AboutInfo.ask).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Support on Ko-fi ☕") { NSWorkspace.shared.open(AboutInfo.koFi) }
                        .buttonStyle(.borderedProminent)
                    Button("GitHub") { NSWorkspace.shared.open(AboutInfo.github) }
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .id(tick) // force status-dot refresh
        .onReceive(refresh) { _ in tick &+= 1 }
        .onAppear { loginOn = LoginItem.isEnabled }
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)

            if interfaces.isEmpty {
                Text("No interfaces found.").font(.caption).foregroundStyle(.secondary)
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
                }
            }
        }
    }
}
