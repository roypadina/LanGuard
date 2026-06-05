import Foundation
import SystemConfiguration

/// A network interface LanGuard cares about (Ethernet or Wi-Fi).
public struct NetInterface: Identifiable, Hashable, Sendable {
    public let bsdName: String      // e.g. "en8"
    public let displayName: String  // e.g. "Realtek USB LAN"
    public let isWiFi: Bool
    /// Bridge / VPN / VM / tunnel adapter — these are off-by-default as triggers
    /// so a virtual NIC (e.g. VMware vmnet) can't pin Wi-Fi off forever.
    public let isVirtual: Bool
    public var id: String { bsdName }

    public init(bsdName: String, displayName: String, isWiFi: Bool, isVirtual: Bool = false) {
        self.bsdName = bsdName
        self.displayName = displayName
        self.isWiFi = isWiFi
        self.isVirtual = isVirtual
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
                out.append(NetInterface(bsdName: bsd, displayName: name, isWiFi: false,
                                        isVirtual: isVirtual(bsdName: bsd, displayName: name)))
            }
        }
        // Stable order by BSD name.
        return out.sorted { $0.bsdName < $1.bsdName }
    }

    public static func wired() -> [NetInterface] { all().filter { !$0.isWiFi } }
    public static func wifi() -> [NetInterface]  { all().filter {  $0.isWiFi } }

    /// Heuristic: is this a virtual / bridge / VPN / VM adapter (not a real cable)?
    /// Pure function (unit-tested). Conservative — only flags clear virtual signatures
    /// so a real USB/Thunderbolt Ethernet adapter is never misclassified.
    public static func isVirtual(bsdName: String, displayName: String) -> Bool {
        let bsd = bsdName.lowercased()
        let name = displayName.lowercased()

        let bsdPrefixes = [
            "bridge", "vmnet", "vnic", "utun", "ppp", "ipsec", "gif", "stf",
            "awdl", "llw", "vlan", "feth", "tap", "tun", "vboxnet",
        ]
        if bsdPrefixes.contains(where: { bsd.hasPrefix($0) }) { return true }

        let nameKeywords = [
            "bridge", "vmware", "parallels", "virtual", "vpn", "tailscale",
            "tunnel", "docker", "virtualbox", "vbox", "hyperkit", "wireguard",
            "tap adapter", "utun",
        ]
        if nameKeywords.contains(where: { name.contains($0) }) { return true }

        return false
    }
}
