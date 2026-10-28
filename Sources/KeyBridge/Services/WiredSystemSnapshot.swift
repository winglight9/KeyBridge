import Foundation
import SystemConfiguration
import Darwin
import KeyBridgeCore

/// Read-only observation. No preference commits, IP changes, or network fallback.
struct WiredSystemSnapshot {
    let configurationAvailable: Bool
    let bridges: [WiredBridgeState]
    var diagnosis: WiredDiagnosis { WiredDiagnosis.evaluate(configurationAvailable: configurationAvailable, bridges: bridges) }
    static func read() -> WiredSystemSnapshot {
        guard let preferences = SCPreferencesCreate(nil, "KeyBridge" as CFString, nil),
              let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else {
            return WiredSystemSnapshot(configurationAvailable: false, bridges: [])
        }
        let store = SCDynamicStoreCreate(nil, "KeyBridge wired diagnostics" as CFString, nil, nil)
        let addressed = interfacesWithAddresses()
        var states: [String: WiredBridgeState] = [:]
        for service in services {
            guard let interface = SCNetworkServiceGetInterface(service),
                  let bsd = SCNetworkInterfaceGetBSDName(interface) as String?, bsd.hasPrefix("bridge") else { continue }
            let labels = [SCNetworkServiceGetName(service) as String?, SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?]
                .compactMap { $0 }.joined(separator: " ").lowercased()
            guard labels.contains("thunderbolt") || labels.contains("雷雳") || labels.contains("雷電") else { continue }
            let link = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Interface/\(bsd)/Link" as CFString) as? [String: Any] }
            let linkActive = (link?[kSCPropNetLinkActive as String] as? NSNumber)?.boolValue
            let enabled = SCNetworkServiceGetEnabled(service) || states[bsd]?.enabled == true
            states[bsd] = WiredBridgeState(name: bsd, enabled: enabled, linkActive: linkActive, hasAddress: addressed.contains(bsd))
        }
        return WiredSystemSnapshot(configurationAvailable: true, bridges: states.values.sorted { $0.name < $1.name })
    }
    private static func interfacesWithAddresses() -> Set<String> {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var result = Set<String>(), current = first
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr, item.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            let family = Int32(address.pointee.sa_family)
            if family == AF_INET {
                let ipv4 = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
                // A self-assigned 169.254 address is valid for this direct link; 0.0.0.0 is not.
                if ipv4 != 0 { result.insert(String(cString: item.pointee.ifa_name)) }
            } else if family == AF_INET6 {
                let ipv6 = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                if withUnsafeBytes(of: ipv6, { $0.contains(where: { $0 != 0 }) }) {
                    result.insert(String(cString: item.pointee.ifa_name))
                }
            }
        }
        return result
    }
}
