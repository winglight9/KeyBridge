import Foundation

/// Facts obtained from SystemConfiguration; a missing link is not a cable capability test.
public struct WiredBridgeState: Equatable {
    public var name: String
    public var enabled: Bool
    public var linkActive: Bool?
    public var hasAddress: Bool
    public init(name: String, enabled: Bool, linkActive: Bool?, hasAddress: Bool) {
        self.name = name; self.enabled = enabled; self.linkActive = linkActive; self.hasAddress = hasAddress
    }
}

public struct WiredDiagnosis: Equatable {
    public enum Stage: String { case configurationUnavailable, bridgeMissing, bridgeDisabled, noLink, linkUnknown, waitingAddress, ready }
    public let stage: Stage
    public let interfaceName: String?
    public var message: String {
        switch stage {
        case .configurationUnavailable: return "Cannot read Thunderbolt network configuration. Retry or copy diagnostics."
        case .bridgeMissing: return "Thunderbolt Bridge is not configured. Check System Settings > Network."
        case .bridgeDisabled: return "Thunderbolt Bridge is disabled. Enable it in System Settings > Network."
        case .noLink: return "No Thunderbolt link detected. Check the cable and ports; this alone does not prove the cable is unsupported."
        case .linkUnknown: return "Thunderbolt link status is unavailable. Check the cable, ports and Thunderbolt Bridge in Network settings."
        case .waitingAddress: return "Thunderbolt link detected; waiting for a network address. Check TCP/IP on both Macs."
        case .ready: return "Thunderbolt network is ready; looking for the other Mac."
        }
    }
    public static func evaluate(configurationAvailable: Bool = true, bridges: [WiredBridgeState]) -> WiredDiagnosis {
        guard configurationAvailable else { return .init(stage: .configurationUnavailable, interfaceName: nil) }
        guard !bridges.isEmpty else { return .init(stage: .bridgeMissing, interfaceName: nil) }
        let enabled = bridges.filter(\.enabled)
        guard !enabled.isEmpty else { return .init(stage: .bridgeDisabled, interfaceName: bridges.first?.name) }
        if let ready = enabled.first(where: { $0.linkActive != false && $0.hasAddress }) {
            return .init(stage: .ready, interfaceName: ready.name)
        }
        if let waiting = enabled.first(where: { $0.linkActive == true }) {
            return .init(stage: .waitingAddress, interfaceName: waiting.name)
        }
        if let unknown = enabled.first(where: { $0.linkActive == nil }) {
            return .init(stage: .linkUnknown, interfaceName: unknown.name)
        }
        return .init(stage: .noLink, interfaceName: enabled.first?.name)
    }
}
