import Foundation
import AppKit
import Network
import Carbon

/// Make-before-break moves between LAN and Wi-Fi.
///
/// A live TCP connection is pinned to the source IP it was opened on. With connection
/// protection on, that IP is the stable address A (see `Protection`), which moves to the new
/// link before the old one goes away — so nothing breaks. Each hand-over brings the new link
/// up, checks it reaches the internet, moves A onto it, and only then cuts Wi-Fi (LAN return)
/// or says it's safe to unplug (Switch to Wi-Fi).
public final class Handover: ObservableObject {

    /// Shown in the menu while a hand-over runs ("Moving traffic to LAN…", "Safe to unplug LAN").
    @Published public private(set) var status: String?

    /// Set by "Switch to Wi-Fi": blocks the automatic LAN hand-over until the LAN is unplugged.
    @Published private var manualWiFi = false
    /// A "Switch to Wi-Fi" is in progress: repeat presses are ignored instead of restarting it.
    @Published private var switching = false

    /// A finished "Switch to Wi-Fi" while the LAN is still plugged in: the menu and shortcut offer "Back to LAN".
    public var switchedToWiFi: Bool { manualWiFi && !switching }
    private var task: Task<Void, Never>?
    private var popupOpen = false
    private let settings: AppSettings
    private let protection: Protection

    init(settings: AppSettings, protection: Protection) { self.settings = settings; self.protection = protection }

    /// LAN came up: keep Wi-Fi on until the LAN reaches the internet and protection has moved
    /// to the LAN, then turn Wi-Fi off. A LAN without internet never cuts Wi-Fi.
    func toLAN(_ wifi: [String], lanName: @escaping () -> String) {
        let on = wifi.filter { WiFiController.isPoweredOn($0) }
        Log.write("toLAN targets=\(wifi) on=\(on) manualWiFi=\(manualWiFi)")
        guard !manualWiFi, !on.isEmpty else { return }
        run {
            self.status = "Waiting for LAN internet…"
            while !(await Probe.reachable(.wiredEthernet)) {
                try await Task.sleep(for: .seconds(2))
            }
            self.status = "Moving traffic to LAN…"
            self.protection.preferWiFi = false
            let iface = await self.protection.settle()
            try Task.checkCancellation()
            if let iface, on.contains(iface) {
                // Protection could not move to the LAN: cutting Wi-Fi now would drop its connections.
                self.status = "Wi-Fi kept on — protection couldn't move to the LAN"
                Log.write("toLAN: protection still on \(iface), Wi-Fi kept on")
                return
            }
            WiFiController.setPower(false, interfaces: on)
            self.status = nil
            if self.settings.notifyMovedToLAN {
                Notifier.post(title: "Wi-Fi off", body: "Traffic is on \(lanName()) — Wi-Fi turned off.")
            }
        }
    }

    /// "Switch to Wi-Fi" (menu / global shortcut): Wi-Fi on → wait until it reaches the internet →
    /// move protection (the stable address) to Wi-Fi → safe to unplug.
    func toWiFi(_ wifi: [String], wired: [String]) {
        Log.write("toWiFi wifi=\(wifi) wired=\(wired) switching=\(switching)")
        guard !switching else { return }
        manualWiFi = true
        switching = true
        run {
            defer { self.switching = false }
            self.status = "Turning Wi-Fi on…"
            if self.settings.switchProgressPopup { ProgressPanel.show(self) }
            WiFiController.setPower(true, interfaces: wifi)
            self.status = "Waiting for Wi-Fi to reach the internet…"
            var up = false
            for _ in 0..<12 {
                up = await Probe.reachable(.wifi)
                if up { break }
                try await Task.sleep(for: .seconds(2))
            }
            guard up else {
                self.status = "Wi-Fi didn't connect — keep the LAN plugged in"
                ProgressPanel.close()
                self.popup("Wi-Fi didn't connect", "Keep the LAN cable plugged in. Wi-Fi was left on to keep trying.")
                return
            }
            self.status = "Moving traffic to Wi-Fi…"
            self.protection.preferWiFi = true
            let iface = await self.protection.settle()
            try Task.checkCancellation()
            let moved = iface.map { wifi.contains($0) } ?? false
            self.status = moved ? "Safe to unplug LAN" : "Wi-Fi connected"
            ProgressPanel.close()
            self.popup(moved ? "Safe to unplug LAN" : "Wi-Fi connected",
                moved ? "Traffic now goes over Wi-Fi. Unplugging the LAN won't drop any connection."
                      : "Protection is off on this network (\(self.protection.status)). "
                        + "Connections opened over the LAN will drop when you unplug.")
        }
    }

    /// Wired link is down: stop any hand-over and close the popup (Protection moves A by itself).
    func lanUnplugged() {
        guard manualWiFi || task != nil || popupOpen else { return }
        reset()
        if popupOpen { NSApp.abortModal() }
    }

    /// Wi-Fi turned off by hand (e.g. Control Center) while the LAN is up: cancel a finished or
    /// stale switch so protection goes back to preferring the LAN. Ignored while a switch is still powering Wi-Fi on.
    func wifiTurnedOff() {
        guard !switching else { return }
        lanUnplugged()
    }

    /// Stop any running hand-over (auto-toggle switched, LAN unplugged).
    func reset() {
        MainActor.assumeIsolated { ProgressPanel.close() }
        switching = false
        task?.cancel()
        task = nil
        manualWiFi = false
        protection.preferWiFi = false
        status = nil
    }

    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            do { try await body() } catch { Log.write("hand-over cancelled") }
        }
    }

    /// Modal alert, run outside the hand-over task. Off via Settings.
    private func popup(_ title: String, _ text: String) {
        guard settings.safeToUnplugPopup else { return }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = text
            NSApp.activate(ignoringOtherApps: true)
            self.popupOpen = true
            alert.runModal()
            self.popupOpen = false
        }
    }
}

/// Internet check scoped to one interface type (works while it isn't the primary).
enum Probe {
    /// True if a TCP connect to 1.1.1.1:443 over `type` succeeds within 3 s.
    static func reachable(_ type: NWInterface.InterfaceType) async -> Bool {
        let params = NWParameters.tcp
        params.requiredInterfaceType = type
        let conn = NWConnection(host: "1.1.1.1", port: 443, using: params)
        return await withCheckedContinuation { cont in
            var done = false
            func finish(_ ok: Bool) {
                guard !done else { return }
                done = true
                conn.cancel()
                cont.resume(returning: ok)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .waiting: finish(false)
                default: break
                }
            }
            conn.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish(false) }
        }
    }
}

/// A recorded shortcut: Carbon key code + Carbon modifier mask, plus its display text.
public struct HotKeyCombo: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var label: String

    public static let `default` = HotKeyCombo(keyCode: UInt32(kVK_ANSI_L),
                                              modifiers: UInt32(controlKey | optionKey | cmdKey), label: "⌃⌥⌘L")

    /// From a key press. Nil without ⌃/⌥/⌘ (a plain key would hijack typing). Pure (unit-tested).
    public init?(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) {
        guard !flags.isDisjoint(with: [.control, .option, .command]) else { return nil }
        var mods: UInt32 = 0, text = ""
        if flags.contains(.control) { mods |= UInt32(controlKey); text += "⌃" }
        if flags.contains(.option) { mods |= UInt32(optionKey); text += "⌥" }
        if flags.contains(.shift) { mods |= UInt32(shiftKey); text += "⇧" }
        if flags.contains(.command) { mods |= UInt32(cmdKey); text += "⌘" }
        let names: [UInt16: String] = [123: "←", 124: "→", 125: "↓", 126: "↑", 49: "Space", 36: "↩",
                                       122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
                                       98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        // Function/arrow keys arrive as private-use or control characters → name them or show the code.
        let chars = (characters ?? "").uppercased()
        let printable = !chars.isEmpty && chars.unicodeScalars.allSatisfy {
            $0.value > 0x20 && !(0xF700...0xF8FF).contains($0.value)
        }
        text += names[keyCode] ?? (printable ? chars : "#\(keyCode)")
        self.init(keyCode: UInt32(keyCode), modifiers: mods, label: text)
    }

    public init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.label = label
    }
}

/// Global "Switch to Wi-Fi" shortcut (Carbon hot key: no Accessibility permission needed).
/// Global = it wins over the same combo inside apps (e.g. cmux) while LanGuard runs.
public enum HotKey {
    private static var action: () -> Void = {}
    private static var ref: EventHotKeyRef?
    /// Last registration result; `eventHotKeyExistsErr` = another app already owns the combo.
    public private(set) static var status: OSStatus = noErr
    public static var inUse: Bool { status == OSStatus(eventHotKeyExistsErr) }

    static func start(_ combo: HotKeyCombo, action: @escaping () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action() }
            return noErr
        }, 1, &spec, nil, nil)
        register(combo)
    }

    public static func register(_ combo: HotKeyCombo) {
        unregister()
        status = RegisterEventHotKey(combo.keyCode, combo.modifiers,
                                     EventHotKeyID(signature: OSType(0x4C4E4744), id: 1), // 'LNGD'
                                     GetApplicationEventTarget(), 0, &ref)
        Log.write("hotkey \(combo.label) register status=\(status)")
    }

    /// Released while recording, so pressing the current combo records it instead of firing.
    public static func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
