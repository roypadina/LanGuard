import XCTest
import AppKit
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

final class ToggleEngineTests: XCTestCase {

    func test_firstRun_wiredUp_turnsWiFiOff() {
        let env = Env(); env.stored = nil; env.wiredActive = ["en8"]
        env.engine().evaluate()
        XCTAssertEqual(env.calls.count, 1)
        XCTAssertEqual(env.calls.first?.on, false)
    }

    func test_firstRun_wiredDown_leavesWiFiAlone() {
        let env = Env(); env.stored = nil; env.wiredActive = []
        env.engine().evaluate()
        XCTAssertTrue(env.calls.isEmpty)
    }

    func test_edgeUp_turnsWiFiOff() {
        let env = Env(); env.stored = false; env.wiredActive = ["en8"]
        env.engine().evaluate()
        XCTAssertEqual(env.calls.map(\.on), [false])
    }

    func test_edgeDown_turnsWiFiOn() {
        let env = Env(); env.stored = true; env.wiredActive = []
        env.engine().evaluate()
        XCTAssertEqual(env.calls.map(\.on), [true])
    }

    func test_noEdge_respectsManualOverride() {
        // Wired stayed up; user manually re-enabled Wi-Fi. App must not touch it.
        let env = Env(); env.stored = true; env.wiredActive = ["en8"]
        env.engine().evaluate()
        XCTAssertTrue(env.calls.isEmpty)
    }

    func test_autoDisabled_neverTouchesWiFi() {
        let env = Env(); env.auto = false; env.stored = false; env.wiredActive = ["en8"]
        env.engine().evaluate()
        XCTAssertTrue(env.calls.isEmpty)
    }

    func test_reapply_enforcesAfresh() {
        let env = Env(); env.stored = true; env.wiredActive = ["en8"]
        let engine = env.engine()   // loads prev = true
        engine.reapply()            // clears edge memory, re-enforces
        XCTAssertEqual(env.calls.map(\.on), [false])
    }
}

final class LoginItemTests: XCTestCase {

    func test_notRegistered_registers() {
        XCTAssertEqual(LoginItem.decide(status: .notRegistered, storedPath: nil, currentPath: "/A"), .register)
    }

    func test_notFound_reRegisters() {
        XCTAssertEqual(LoginItem.decide(status: .notFound, storedPath: "/A", currentPath: "/A"), .reRegisterMoved)
    }

    func test_enabledSamePath_none() {
        XCTAssertEqual(LoginItem.decide(status: .enabled, storedPath: "/A", currentPath: "/A"), .none)
    }

    func test_enabledNoStoredPath_none() {
        XCTAssertEqual(LoginItem.decide(status: .enabled, storedPath: nil, currentPath: "/A"), .none)
    }

    func test_movedWhileEnabled_reRegisters() {
        XCTAssertEqual(LoginItem.decide(status: .enabled, storedPath: "/A", currentPath: "/B"), .reRegisterMoved)
    }

    func test_movedWhileApprovalPending_reRegisters() {
        XCTAssertEqual(LoginItem.decide(status: .requiresApproval, storedPath: "/A", currentPath: "/B"), .reRegisterMoved)
    }
}

final class InterfaceCatalogTests: XCTestCase {

    func test_virtual_flagsBridgeVpnVm() {
        XCTAssertTrue(InterfaceCatalog.isVirtual(bsdName: "bridge0", displayName: "Thunderbolt Bridge"))
        XCTAssertTrue(InterfaceCatalog.isVirtual(bsdName: "vmnet8", displayName: "vmnet8"))
        XCTAssertTrue(InterfaceCatalog.isVirtual(bsdName: "utun4", displayName: "utun4"))
        XCTAssertTrue(InterfaceCatalog.isVirtual(bsdName: "en5", displayName: "Parallels Adapter"))
        XCTAssertTrue(InterfaceCatalog.isVirtual(bsdName: "vboxnet0", displayName: "VirtualBox Host-Only"))
    }

    func test_virtual_keepsRealAdaptersPhysical() {
        XCTAssertFalse(InterfaceCatalog.isVirtual(bsdName: "en8", displayName: "Realtek USB LAN"))
        XCTAssertFalse(InterfaceCatalog.isVirtual(bsdName: "en1", displayName: "Thunderbolt 1"))
        XCTAssertFalse(InterfaceCatalog.isVirtual(bsdName: "en0", displayName: "Ethernet"))
    }
}

final class MenuStateTests: XCTestCase {

    func test_mapping() {
        XCTAssertEqual(MenuState.from(autoEnabled: false, wiredUp: true), .paused)
        XCTAssertEqual(MenuState.from(autoEnabled: false, wiredUp: false), .paused)
        XCTAssertEqual(MenuState.from(autoEnabled: true, wiredUp: true), .lan)
        XCTAssertEqual(MenuState.from(autoEnabled: true, wiredUp: false), .wifi)
    }
}

final class AppSettingsTests: XCTestCase {

    func test_physicalOptOut_virtualOptIn() {
        let defaults = UserDefaults(suiteName: "lg-test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let phys = NetInterface(bsdName: "en8", displayName: "Realtek USB LAN", isWiFi: false, isVirtual: false)
        let virt = NetInterface(bsdName: "bridge0", displayName: "Thunderbolt Bridge", isWiFi: false, isVirtual: true)

        // Defaults: physical on, virtual off.
        XCTAssertTrue(settings.wiredEnabled(phys))
        XCTAssertFalse(settings.wiredEnabled(virt))

        // User can opt a virtual adapter in, and opt a physical one out.
        settings.setWiredEnabled(virt, true)
        settings.setWiredEnabled(phys, false)
        XCTAssertTrue(settings.wiredEnabled(virt))
        XCTAssertFalse(settings.wiredEnabled(phys))
    }
}

final class ProtectionTests: XCTestCase {

    func test_target_prefersWiredUnlessSwitched() {
        XCTAssertEqual(Protection.target(preferWiFi: false, wired: "en7", wifi: "en0"), "en7")
        XCTAssertEqual(Protection.target(preferWiFi: true, wired: "en7", wifi: "en0"), "en0")
        XCTAssertEqual(Protection.target(preferWiFi: false, wired: nil, wifi: "en0"), "en0")   // LAN unplugged
        XCTAssertEqual(Protection.target(preferWiFi: true, wired: "en7", wifi: nil), "en7")    // Wi-Fi not up yet
        XCTAssertNil(Protection.target(preferWiFi: false, wired: nil, wifi: nil))
    }

    func test_candidates_topOfSubnetDown_skipsBroadcastAndExcludes() {
        let c = Protection.candidates(ip: "192.168.1.16", mask: "255.255.255.0",
                                      exclude: ["192.168.1.16", "192.168.1.1", "192.168.1.253"], count: 3)
        XCTAssertEqual(c, ["192.168.1.254", "192.168.1.252", "192.168.1.251"])
    }

    func test_candidates_smallSubnetNeverReturnsNetworkAddress() {
        let c = Protection.candidates(ip: "10.0.0.2", mask: "255.255.255.252", exclude: ["10.0.0.2"])
        XCTAssertEqual(c, ["10.0.0.1"])                                   // /30: .3 broadcast, .0 network
        XCTAssertEqual(Protection.candidates(ip: "10.0.0.2", mask: "255.255.255.255", exclude: []), [])
        XCTAssertEqual(Protection.candidates(ip: "bad", mask: "255.255.255.0", exclude: []), [])
    }
}

final class HotKeyComboTests: XCTestCase {

    func test_recordsComboWithLabel() {
        let combo = HotKeyCombo(keyCode: 37, flags: [.control, .option, .command], characters: "l")
        XCTAssertEqual(combo?.label, "⌃⌥⌘L")
        XCTAssertEqual(combo, .default)
    }

    func test_plainOrShiftOnlyKeyRejected() {
        XCTAssertNil(HotKeyCombo(keyCode: 37, flags: [], characters: "l"))
        XCTAssertNil(HotKeyCombo(keyCode: 37, flags: [.shift], characters: "L"))
    }

    func test_specialKeysNamedOrCoded() {
        XCTAssertEqual(HotKeyCombo(keyCode: 123, flags: [.shift, .command], characters: "\u{F702}")?.label, "⇧⌘←")
        XCTAssertEqual(HotKeyCombo(keyCode: 105, flags: [.control], characters: "\u{F710}")?.label, "⌃#105")
    }
}
