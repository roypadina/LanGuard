import Foundation
import SystemConfiguration

/// A network interface LanGuard cares about (Ethernet or Wi-Fi).
public struct NetInterface: Identifiable, Hashable, Sendable {
    public let bsdName: String      // e.g. "en8"
    public let displayName: String  // e.g. "Realtek USB LAN"
    public let isWiFi: Bool
    public var id: String { bsdName }

    public init(bsdName: String, displayName: String, isWiFi: Bool) {
        self.bsdName = bsdName
        self.displayName = displayName
        self.isWiFi = isWiFi
    }
}

/// Enumerates and classifies the machine's Ethernet / Wi-Fi interfaces.
public enum InterfaceCatalog {

    /// All Ethernet + Wi-Fi hardware interfaces, classified.
    public static func all() -> [NetInterface] {
        guard let raw = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [] }
        var out: [NetInterface] = []
        let wifiType = kSCNetworkInterfaceTypeIEEE80211 as String
        let ethType = kSCNetworkInterfaceTypeEthernet as String

        for iface in raw {
            guard let bsd = SCNetworkInterfaceGetBSDName(iface) as String? else { continue }
            let type = SCNetworkInterfaceGetInterfaceType(iface) as String?
            let name = (SCNetworkInterfaceGetLocalizedDisplayName(iface) as String?) ?? bsd
            if type == wifiType {
                out.append(NetInterface(bsdName: bsd, displayName: name, isWiFi: true))
            } else if type == ethType {
                out.append(NetInterface(bsdName: bsd, displayName: name, isWiFi: false))
            }
        }
        // Stable order by BSD name.
        return out.sorted { $0.bsdName < $1.bsdName }
    }

    public static func wired() -> [NetInterface] { all().filter { !$0.isWiFi } }
    public static func wifi() -> [NetInterface]  { all().filter {  $0.isWiFi } }
}
