import Foundation
import Network
import SystemConfiguration
import Darwin
import KeyBridgeCore

/// Discovery and connections are confined to the system's Thunderbolt Bridge.
final class WiredTransport: BridgeTransport {
    var onDevices: (([DiscoveredDevice]) -> Void)?
    var onLink: ((DataLink) -> Void)?
    var onStatus: ((String) -> Void)?
    private let queue = DispatchQueue(label: "org.keybridge.wired")
    private var monitor: NWPathMonitor?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var results: [String: NWEndpoint] = [:]
    private var interfaceName: String?
    private var active: DataLink?
    private var generation = UUID()
    private var running = false
    private var poller: Timer?
    private var snapshot = WiredSystemSnapshot(configurationAvailable: false, bridges: [])
    private var lastStatus = ""
    private var networkIssues: [String:String] = [:]
    private var networkIssue: String? { networkIssues.keys.sorted().first.flatMap { networkIssues[$0] } }
    private var discoveryBegan = 0.0
    var diagnosticSummary: [String: Any] {
        ["stage": snapshot.diagnosis.stage.rawValue,
         "status": lastStatus,
         "interface": interfaceName ?? snapshot.diagnosis.interfaceName ?? "",
         "configuredBridges": snapshot.bridges.map { bridge -> [String: Any] in
             ["name": bridge.name, "enabled": bridge.enabled,
              "linkActive": bridge.linkActive.map { $0 as Any } ?? NSNull(), "hasAddress": bridge.hasAddress]
         }]
    }
    var needsAttention: Bool {
        snapshot.diagnosis.stage != .ready || interfaceName == nil || networkIssue != nil ||
        (active?.closed != false && results.isEmpty && ProcessInfo.processInfo.systemUptime - discoveryBegan >= 8)
    }
    private func report(_ message: String) {
        guard message != lastStatus else { return }
        lastStatus = message; onStatus?(message)
    }
    private func reportDiscovery() {
        guard active?.closed != false else { return }
        if let networkIssue { report(networkIssue) }
        else if !results.isEmpty { report("Thunderbolt network is ready; select the other Mac to connect.") }
        else if ProcessInfo.processInfo.systemUptime - discoveryBegan >= 8 {
            report("Thunderbolt network is ready, but no other KeyBridge was discovered. Open KeyBridge on the other Mac and check local-network permission.")
        } else { report(snapshot.diagnosis.message) }
    }
    private func report(_ error: NWError, source: String = "connection") {
        let message: String
        switch error {
        case .dns(let code) where code == -65570:
            message = "Network discovery was denied by macOS. Check local-network permission and network policies."
        case .posix(let code) where code == .EACCES || code == .EPERM:
            message = "Network access was denied by macOS. Check permissions and network security policies."
        default: message = "Wired network error: " + error.localizedDescription
        }
        networkIssues[source] = message; report(message)
    }

    func start() {
        stop(); running = true
        let monitor = NWPathMonitor(); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.update(path) }
        }
        monitor.start(queue: queue)
        poller = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, let path = self.monitor?.currentPath else { return }; self.update(path)
        }
    }
    private func update(_ path: NWPath) {
        guard running else { return }
        snapshot = WiredSystemSnapshot.read()
        let diagnosis = snapshot.diagnosis
        guard diagnosis.stage == .ready else {
            if interfaceName != nil {
                stopNetwork(); active?.close("Wired link disconnected"); active = nil
            }
            interfaceName = nil; report(diagnosis.message); return
        }
        guard let interface = path.availableInterfaces.first(where: { $0.name == diagnosis.interfaceName }) else {
            if interfaceName != nil { stopNetwork(); active?.close("Wired link disconnected"); active = nil }
            interfaceName = nil
            report("Thunderbolt has a network address, but its interface is unavailable to the app. Retry or copy diagnostics."); return
        }
        guard interface.name != interfaceName else { reportDiscovery(); return }
        stopNetwork(); interfaceName = interface.name
        discoveryBegan = ProcessInfo.processInfo.systemUptime
        let params = NWParameters.tcp
        params.requiredInterface = interface
        params.includePeerToPeer = false
        params.allowLocalEndpointReuse = true
        let token = UUID(); generation = token
        do {
            let server = try NWListener(using: params, on: .any)
            server.service = NWListener.Service(name: IdentityVault.networkName, type: "_keybridge._tcp")
            server.newConnectionHandler = { [weak self] connection in
                DispatchQueue.main.async { guard self?.generation == token else { connection.cancel(); return }; self?.accept(connection, name: "Incoming direct link") }
            }
            server.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed(let error), .waiting(let error):
                    DispatchQueue.main.async { if self?.generation == token { self?.report(error, source: "listener") } }
                case .ready:
                    DispatchQueue.main.async { if self?.generation == token { self?.networkIssues.removeValue(forKey: "listener"); self?.reportDiscovery() } }
                default: break
                }
            }
            listener = server; server.start(queue: queue)
            let browser = NWBrowser(for: .bonjour(type: "_keybridge._tcp", domain: nil), using: params)
            browser.browseResultsChangedHandler = { [weak self] found, _ in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    var entries: [DiscoveredDevice] = []; self.results.removeAll()
                    for result in found {
                        guard case .service(let name, _, _, _) = result.endpoint,
                              name != IdentityVault.networkName else { continue }
                        let id = "wired:" + String(describing: result.endpoint)
                        self.results[id] = result.endpoint; entries.append(DiscoveredDevice(id: id, name: name))
                    }
                    self.onDevices?(entries.sorted { $0.name < $1.name }); self.reportDiscovery()
                }
            }
            browser.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed(let error), .waiting(let error):
                    DispatchQueue.main.async { if self?.generation == token { self?.report(error, source: "browser") } }
                case .ready:
                    DispatchQueue.main.async { if self?.generation == token { self?.networkIssues.removeValue(forKey: "browser"); self?.reportDiscovery() } }
                default: break
                }
            }
            self.browser = browser; browser.start(queue: queue)
            reportDiscovery()
        } catch {
            let message = "Wired network error: " + error.localizedDescription
            networkIssues["listener"] = message; report(message)
        }
    }
    func connect(_ id: String) {
        guard let endpoint = results[id], let interface = monitor?.currentPath.availableInterfaces.first(where: { $0.name == interfaceName }) else {
            report("Direct device is no longer available"); return
        }
        let params = NWParameters.tcp; params.requiredInterface = interface; params.includePeerToPeer = false
        if let options = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options { options.noDelay = true }
        accept(NWConnection(to: endpoint, using: params), name: String(describing: endpoint))
    }
    private func accept(_ connection: NWConnection, name: String) {
        active?.close("Replaced connection")
        let link = DataLink(name: name); active = link
        var pendingBytes = 0
        link.writer = { [weak link] data in
            guard pendingBytes + data.count < 262_144 else { link?.close("Send queue full"); return }
            pendingBytes += data.count
            connection.send(content: data, completion: .contentProcessed { error in
                DispatchQueue.main.async { pendingBytes -= data.count; if let error { link?.close(error.localizedDescription) } }
            })
        }
        link.closer = { connection.cancel() }
        var opened = false
        connection.stateUpdateHandler = { [weak self, weak link] state in
            DispatchQueue.main.async {
                guard let self, let link, !link.closed else { return }
                switch state {
                case .ready:
                    self.networkIssues.removeValue(forKey: "connection")
                    if !opened { opened = true; self.onLink?(link); self.receive(connection, link: link) }
                case .failed(let error): link.close(error.localizedDescription)
                case .waiting(let error): self.report(error)
                case .cancelled: link.close("Wired link closed")
                default: break
                }
            }
        }
        connection.start(queue: queue)
    }
    private func receive(_ connection: NWConnection, link: DataLink) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak link] data, _, complete, error in
            DispatchQueue.main.async {
                guard let self, let link, !link.closed else { return }
                if let data, !data.isEmpty { link.receive(data) }
                if let error { link.close(error.localizedDescription) }
                else if complete { link.close("Wired peer disconnected") }
                else { self.receive(connection, link: link) }
            }
        }
    }
    func stop() {
        running = false; poller?.invalidate(); poller = nil; generation = UUID(); monitor?.cancel(); monitor = nil
        stopNetwork(); active?.close(); active = nil; interfaceName = nil; lastStatus = ""
    }
    private func stopNetwork() {
        generation = UUID(); listener?.cancel(); browser?.cancel(); listener = nil; browser = nil
        results.removeAll(); networkIssues.removeAll(); onDevices?([])
    }
    static func thunderboltBridges() -> Set<String> {
        Set(WiredSystemSnapshot.read().bridges.map(\.name))
    }
}
