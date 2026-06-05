import Testing
import ServiceManagement
@testable import LanGuardFeature

/// Mutable test environment backing ToggleEngine's injected dependencies.
private final class Env {
    var wiredActive: [String] = []
    var auto = true
    var stored: Bool?
    var calls: [(on: Bool, names: [String])] = []

    func engine() -> ToggleEngine {
        ToggleEngine(dependencies: .init(
            activeWiredNames: { self.wiredActive },
            wifiTargets: { ["en0"] },
            setWiFiPower: { on, names in self.calls.append((on, names)) },
            anyWiFiOn: { false },
            autoEnabled: { self.auto },
            saveLastWired: { self.stored = $0 },
            loadLastWired: { self.stored }
        ))
    }
}

@Test func firstRun_wiredUp_turnsWiFiOff() {
    let env = Env(); env.stored = nil; env.wiredActive = ["en8"]
    env.engine().evaluate()
    #expect(env.calls.count == 1)
    #expect(env.calls.first?.on == false)
}

@Test func firstRun_wiredDown_leavesWiFiAlone() {
    let env = Env(); env.stored = nil; env.wiredActive = []
    env.engine().evaluate()
    #expect(env.calls.isEmpty)
}

@Test func edgeUp_turnsWiFiOff() {
    let env = Env(); env.stored = false; env.wiredActive = ["en8"]
    env.engine().evaluate()
    #expect(env.calls.map(\.on) == [false])
}

@Test func edgeDown_turnsWiFiOn() {
    let env = Env(); env.stored = true; env.wiredActive = []
    env.engine().evaluate()
    #expect(env.calls.map(\.on) == [true])
}

@Test func noEdge_respectsManualOverride() {
    // Wired stayed up; user manually re-enabled Wi-Fi. App must not touch it.
    let env = Env(); env.stored = true; env.wiredActive = ["en8"]
    env.engine().evaluate()
    #expect(env.calls.isEmpty)
}

@Test func autoDisabled_neverTouchesWiFi() {
    let env = Env(); env.auto = false; env.stored = false; env.wiredActive = ["en8"]
    env.engine().evaluate()
    #expect(env.calls.isEmpty)
}

@Test func reapply_enforcesAfresh() {
    let env = Env(); env.stored = true; env.wiredActive = ["en8"]
    let engine = env.engine()           // loads prev = true
    engine.reapply()                    // clears edge memory, re-enforces
    #expect(env.calls.map(\.on) == [false])
}

// MARK: - Login-item registration decision

@Test func login_notRegistered_registers() {
    #expect(LoginItem.decide(status: .notRegistered, storedPath: nil, currentPath: "/A") == .register)
}

@Test func login_notFound_reRegisters() {
    #expect(LoginItem.decide(status: .notFound, storedPath: "/A", currentPath: "/A") == .reRegisterMoved)
}

@Test func login_enabledSamePath_none() {
    #expect(LoginItem.decide(status: .enabled, storedPath: "/A", currentPath: "/A") == .none)
}

@Test func login_enabledNoStoredPath_none() {
    // Already enabled, first time recording the path → adopt, don't re-register.
    #expect(LoginItem.decide(status: .enabled, storedPath: nil, currentPath: "/A") == .none)
}

@Test func login_movedWhileEnabled_reRegisters() {
    #expect(LoginItem.decide(status: .enabled, storedPath: "/A", currentPath: "/B") == .reRegisterMoved)
}

@Test func login_movedWhileApprovalPending_reRegisters() {
    #expect(LoginItem.decide(status: .requiresApproval, storedPath: "/A", currentPath: "/B") == .reRegisterMoved)
}

// MARK: - Virtual-adapter detection

@Test func virtual_flagsBridgeVpnVm() {
    #expect(InterfaceCatalog.isVirtual(bsdName: "bridge0", displayName: "Thunderbolt Bridge"))
    #expect(InterfaceCatalog.isVirtual(bsdName: "vmnet8", displayName: "vmnet8"))
    #expect(InterfaceCatalog.isVirtual(bsdName: "utun4", displayName: "utun4"))
    #expect(InterfaceCatalog.isVirtual(bsdName: "en5", displayName: "Parallels Adapter"))
    #expect(InterfaceCatalog.isVirtual(bsdName: "vboxnet0", displayName: "VirtualBox Host-Only"))
}

@Test func virtual_keepsRealAdaptersPhysical() {
    #expect(!InterfaceCatalog.isVirtual(bsdName: "en8", displayName: "Realtek USB LAN"))
    #expect(!InterfaceCatalog.isVirtual(bsdName: "en1", displayName: "Thunderbolt 1"))
    #expect(!InterfaceCatalog.isVirtual(bsdName: "en0", displayName: "Ethernet"))
}

// MARK: - Settings: virtual opt-in vs physical opt-out

@Test func settings_physicalOptOut_virtualOptIn() {
    let defaults = UserDefaults(suiteName: "lg-test-\(UUID().uuidString)")!
    let settings = AppSettings(defaults: defaults)
    let phys = NetInterface(bsdName: "en8", displayName: "Realtek USB LAN", isWiFi: false, isVirtual: false)
    let virt = NetInterface(bsdName: "bridge0", displayName: "Thunderbolt Bridge", isWiFi: false, isVirtual: true)

    // Defaults: physical on, virtual off.
    #expect(settings.wiredEnabled(phys) == true)
    #expect(settings.wiredEnabled(virt) == false)

    // User can opt a virtual adapter in, and opt a physical one out.
    settings.setWiredEnabled(virt, true)
    settings.setWiredEnabled(phys, false)
    #expect(settings.wiredEnabled(virt) == true)
    #expect(settings.wiredEnabled(phys) == false)
}
