import Testing
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
