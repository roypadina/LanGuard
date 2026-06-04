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

        Button("Quit LanGuard") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
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

            Toggle("Start at login", isOn: $loginOn)
                .onChange(of: loginOn) { _, newValue in
                    LoginItem.setEnabled(newValue)
                    loginOn = LoginItem.isEnabled
                }

            Divider()

            section(
                title: "Wired triggers",
                subtitle: "Wi-Fi turns off when any checked wired link is active.",
                interfaces: wired,
                isActive: { model.linkActive($0) },
                isOn: { model.settings.wiredEnabled($0) },
                set: { bsd, on in
                    model.settings.setWiredEnabled(bsd, on)
                    model.selectionChanged()
                }
            )

            Divider()

            section(
                title: "Controlled Wi-Fi",
                subtitle: "These adapters get switched on/off.",
                interfaces: wifi,
                isActive: { model.wifiPoweredOn($0) },
                isOn: { model.settings.wifiEnabled($0) },
                set: { bsd, on in
                    model.settings.setWiFiEnabled(bsd, on)
                    model.selectionChanged()
                }
            )
        }
        .padding(20)
        .frame(width: 420)
        .id(tick) // force status-dot refresh
        .onReceive(refresh) { _ in tick &+= 1 }
        .onAppear { loginOn = LoginItem.isEnabled }
    }

    @ViewBuilder
    private func section(
        title: String,
        subtitle: String,
        interfaces: [NetInterface],
        isActive: @escaping (String) -> Bool,
        isOn: @escaping (String) -> Bool,
        set: @escaping (String, Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)

            if interfaces.isEmpty {
                Text("No interfaces found.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(interfaces) { iface in
                    Toggle(isOn: Binding(
                        get: { isOn(iface.bsdName) },
                        set: { set(iface.bsdName, $0) }
                    )) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isActive(iface.bsdName) ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text("\(iface.displayName)  (\(iface.bsdName))")
                        }
                    }
                }
            }
        }
    }
}
