import Foundation
import CoreWLAN

/// Reads and sets Wi-Fi interface power via CoreWLAN (no sudo, no shell).
public enum WiFiController {

    struct InterfaceNotFound: Error { let name: String }

    /// Powers one interface; throws on failure. Replaced by tests.
    static var applyPower: (_ name: String, _ on: Bool) throws -> Void = { name, on in
        guard let iface = CWWiFiClient.shared().interface(withName: name) else { throw InterfaceNotFound(name: name) }
        try iface.setPower(on)
    }

    /// Set power on/off for the given Wi-Fi BSD names (e.g. ["en0"]).
    /// False if any interface could not be set (callers must not announce the change then).
    @discardableResult
    public static func setPower(_ on: Bool, interfaces: [String]) -> Bool {
        var ok = true
        for name in interfaces {
            do {
                try applyPower(name, on)
            } catch {
                ok = false
                NSLog("LanGuard: setPower(\(on)) failed for \(name): \(error)")
                Log.write("setPower(\(on)) FAILED for \(name): \(error)")
            }
        }
        return ok
    }

    /// True if the named Wi-Fi interface is currently powered on.
    public static func isPoweredOn(_ name: String) -> Bool {
        CWWiFiClient.shared().interface(withName: name)?.powerOn() ?? false
    }
}
