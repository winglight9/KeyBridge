import AppKit
import Combine
import KeyBridgeCore
import OSLog

enum ConnectionPhase { case searching, connecting, pairing, connected, unstable, disconnected }
struct DeviceOption: Identifiable { var id: String; var name: String; var canSource: Bool }

final class BridgeStore: ObservableObject {
    @Published var language: String { didSet { UserDefaults.standard.set(language, forKey: "language") } }
    @Published private(set) var mode: LinkMode = .wired
    @Published private(set) var phase: ConnectionPhase = .searching
    @Published private(set) var local: DeviceIdentity
    @Published private(set) var peer: DeviceIdentity?
    @Published private(set) var discoveries: [DiscoveredDevice] = []
    @Published private(set) var sourceID: String
    @Published private(set) var targetID: String
    @Published private(set) var forwarding = false
    @Published private(set) var detail = ""
    @Published private(set) var error = ""
    @Published private(set) var pairingCode = ""
    @Published private(set) var identityChanged = false
    @Published private(set) var localPairApproved = false
    @Published private(set) var identityLoading = false
    @Published private(set) var identityNeedsAuthorization = false
    @Published private(set) var latency: Double?
    @Published private(set) var inputPermission = HIDCatalog.allowed
    @Published private(set) var receivePermission = InputInjector.allowed
    @Published var confirmMode: LinkMode?
    /// This Mac's source capture only; the authenticated receiving Mac advertises decode support.
    @Published var gestureForwardingEnabled = UserDefaults.standard.bool(forKey:"native-gestures") {
        didSet {
            UserDefaults.standard.set(gestureForwardingEnabled,forKey:"native-gestures")
            if gestureForwardingEnabled != oldValue { stopForwarding() }
        }
    }
    private let log = Logger(subsystem: "org.keybridge.app", category: "Connection")
    private let capture = DeviceEventCapture()
    private let injector = InputInjector()
    private var vault: IdentityVault?
    private var transport: BridgeTransport?
    private var link: DataLink?
    private var session: SecureSession?
    private var route: Route?
    private var captureStartingToken: String?
    // A selection belongs to the pair of Macs, independently of the selected link.
    private struct SavedSelection: Codable {
        var route: Route
        var modifiedAt: Double
    }
    private var savedSelection: SavedSelection?
    private var selectionKey: String? {
        guard let peer else { return nil }
        return "route-selection." + [local.id, peer.id].sorted().joined(separator: ".")
    }
    private var heartbeat: Timer?
    private var lastReceived = ProcessInfo.processInfo.systemUptime
    private var connectionBegan = 0.0
    private var lastHardwareRefresh = 0.0
    private var lastIdentityRefresh = 0.0
    private var pendingIntent: String?
    private var requestedDiscovery: String?
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []
    private var stopped = false
    private var reconnectRequested = false
    private var startupReconnect = false
    private var startupReconnectScheduled = false

    init(initialMode: LinkMode? = nil) {
        language = UserDefaults.standard.string(forKey: "language") ?? (Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en")
        let endpoints = HIDCatalog.scan()
        let identity = DeviceIdentity(id: "unavailable", name: IdentityVault.networkName,
            keyboard: endpoints.contains { $0.kind == .keyboard }, trackpad: endpoints.contains { $0.kind == .trackpad }, canReceive: InputInjector.allowed)
        local = identity; sourceID = identity.id; targetID = identity.id
        mode = initialMode ?? LinkMode(rawValue:UserDefaults.standard.string(forKey:"selected-link") ?? "") ?? .wired
        if initialMode != nil { UserDefaults.standard.set(mode.rawValue,forKey:"selected-link") }
        requestedDiscovery = UserDefaults.standard.string(forKey:"last-discovery." + mode.rawValue)
        reconnectRequested = requestedDiscovery != nil; startupReconnect = reconnectRequested
        pendingIntent = reconnectRequested ? "connect" : nil
        capture.onFailure = { [weak self] text in
            guard let self else { return }; self.stopForwarding(); self.error = text
        }
        heartbeat = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        if let heartbeat { RunLoop.main.add(heartbeat, forMode: .common) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.disconnect("Mac is sleeping") })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.shutdown() })
        prepareIdentity()
    }
    private func prepareIdentity() {
        guard !identityLoading, !stopped else { return }
        identityLoading = true; identityNeedsAuthorization = false; error = ""
        detail = text("Preparing device identity…", "正在准备设备身份…")
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result = Result { try IdentityVault() }
            DispatchQueue.main.async {
                guard let self, !self.stopped else { return }; self.identityLoading = false
                switch result {
                case .success(let vault):
                    self.vault = vault; self.local.id = vault.id; self.sourceID = vault.id; self.targetID = vault.id
                    self.startTransport()
                case .failure(let error):
                    self.identityNeedsAuthorization = true; self.phase = .disconnected
                    self.error = self.text("Cannot load this Mac's device identity. Retry or copy diagnostics.", "无法读取本机的设备身份，请重试或复制诊断信息。")
                    self.detail = error.localizedDescription
                }
            }
        }
    }
    func allowIdentityAccess() { prepareIdentity() }
    var chinese: Bool { language == "zh" }
    var inputStatistics: [String:Int] { capture.statistics }
    var receivedInputStatistics: [String:Int] { injector.statistics }
    var routeToken: String? { route?.token }
    var wiredDiagnostics: [String:Any] { (transport as? WiredTransport)?.diagnosticSummary ?? [:] }
    func text(_ english: String, _ chinese: String) -> String { self.chinese ? chinese : english }
    var appName: String { text("KeyBridge", "键桥") }
    var options: [DeviceOption] {
        var values = [DeviceOption(id: local.id, name: local.name, canSource: local.keyboard)]
        if let peer { values.append(DeviceOption(id: peer.id, name: peer.name, canSource: peer.keyboard)) }
        if peer == nil {
            values += discoveries.map { DeviceOption(id: "discovery:" + $0.id, name: $0.name, canSource: true) }
        }
        return values
    }
    var ready: Bool { session?.ready == true }
    var status: String {
        switch phase {
        case .searching: return text("Looking for devices", "正在发现设备")
        case .connecting: return text("Connecting…", "正在连接…")
        case .pairing: return text("Confirm pairing", "请确认配对")
        case .connected: return mode == .wired ? text("Connected · Wired", "已连接 · 有线") : text("Connected · Bluetooth", "已连接 · 蓝牙")
        case .unstable: return text("Link unstable", "连接不稳定")
        case .disconnected: return text("Disconnected", "已断开")
        }
    }
    var routeDescription: String {
        if forwarding {
            let destination = targetID == local.id ? local.name : peer?.name ?? ""
            return text("Keyboard and trackpad → ", "键盘与触摸板 → ") + destination
        }
        return text("Input stays on its source Mac.", "键盘与触摸板保留在来源 Mac 上。")
    }
    func chooseSource(_ id: String) {
        if id.hasPrefix("discovery:") { connectDiscovery(String(id.dropFirst(10)), intent: "source"); return }
        sourceID = id; applySelection()
    }
    func chooseTarget(_ id: String) {
        if id.hasPrefix("discovery:") { connectDiscovery(String(id.dropFirst(10)), intent: "target"); return }
        targetID = id; applySelection()
    }
    private func connectDiscovery(_ id: String, intent: String) {
        guard vault != nil else { return }
        reconnectRequested = false; startupReconnect = false
        pendingIntent = intent; requestedDiscovery = id; error = ""; phase = .connecting
        connectionBegan = ProcessInfo.processInfo.systemUptime; transport?.connect(id)
    }
    func retry() {
        if vault == nil { prepareIdentity(); return }
        let last = requestedDiscovery ?? UserDefaults.standard.string(forKey:"last-discovery." + mode.rawValue)
        disconnect("Retrying connection"); requestedDiscovery = last
        reconnectRequested = last != nil; startupReconnect = false; pendingIntent = "connect"; startTransport()
        if last != nil { phase = .connecting; connectionBegan = ProcessInfo.processInfo.systemUptime }
    }
    func requestMode(_ selection: LinkMode) {
        if selection != mode { confirmMode = selection }
    }
    func switchMode() {
        guard let selection = confirmMode else { return }
        confirmMode = nil; disconnect("Connection mode changed"); mode = selection
        UserDefaults.standard.set(mode.rawValue,forKey:"selected-link")
        requestedDiscovery = UserDefaults.standard.string(forKey:"last-discovery." + mode.rawValue)
        pendingIntent = nil; startTransport()
    }
    private func startTransport() {
        generation = UUID(); let token = generation; startupReconnectScheduled = false
        transport?.stop(); discoveries = []; phase = .searching; detail = ""; error = ""
        let service: BridgeTransport = mode == .wired ? WiredTransport() : BluetoothTransport()
        service.onDevices = { [weak self] devices in
            guard let self, self.generation == token else { return }; self.discoveries = devices
            if self.reconnectRequested, let last = self.requestedDiscovery,
               let device = devices.first(where: { $0.id == last }) {
                // Both Macs remember one another. Elect one startup dialer so two simultaneous
                // outgoing connections cannot replace the other end's incoming connection.
                if !self.startupReconnect || self.local.name < device.name {
                    self.connectDiscovery(last,intent:"connect")
                } else if !self.startupReconnectScheduled {
                    self.startupReconnectScheduled = true
                    // The other Mac may have no saved peer yet. Give its preferred dialer
                    // time to connect, then fall back once on this same discovered link.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        guard let self, self.generation == token, self.startupReconnect,
                              self.reconnectRequested, self.link == nil,
                              self.requestedDiscovery == last,
                              self.discoveries.contains(where: { $0.id == last }) else { return }
                        self.connectDiscovery(last, intent: "connect")
                    }
                }
            }
        }
        service.onStatus = { [weak self] message in
            guard let self, self.generation == token else { return }
            self.detail = message
            if !self.ready, self.phase != .pairing, self.phase != .connecting {
                let wiredIssue = (self.transport as? WiredTransport)?.needsAttention == true
                self.phase = wiredIssue || message.hasPrefix("No ") || message.contains("off") || message.contains("required") ? .disconnected : .searching
            }
        }
        service.onLink = { [weak self] link in
            guard let self, self.generation == token else { link.close(); return }; self.establish(link)
        }
        transport = service; service.start()
    }
    private func establish(_ link: DataLink) {
        guard let vault else { link.close(); return }
        reconnectRequested = false; startupReconnect = false
        self.link?.onClosed = nil; self.link?.close("New connection")
        stopLocalInput(); self.link = link; phase = .connecting; error = ""; pairingCode = ""; localPairApproved = false
        connectionBegan = ProcessInfo.processInfo.systemUptime
        refreshIdentity()
        let session = SecureSession(identity: local, signingKey: vault.signingKey, pin: { vault.pinned($0) })
        self.session = session
        session.sendWire = { [weak link] data in link?.send(data) }
        link.onPacket = { [weak session] data in session?.receive(data) }
        link.onClosed = { [weak self, weak link] reason in
            guard let self, self.link === link else { return }; self.disconnect(reason)
        }
        session.onPairing = { [weak self] identity, code, changed in
            guard let self else { return }
            self.peer = identity; self.pairingCode = code; self.identityChanged = changed; self.phase = .pairing
            self.connectionBegan = ProcessInfo.processInfo.systemUptime // allow time to change monitor input and approve both Macs
        }
        session.onReady = { [weak self] identity, fingerprint in
            guard let self else { return }
            self.peer = identity; vault.trust(identity.id, fingerprint: fingerprint)
            if let id = (self.transport as? BluetoothTransport)?.rememberName(identity.name) { self.requestedDiscovery = id }
            else if let found = self.discoveries.first(where:{ $0.name == identity.name }) { self.requestedDiscovery = found.id }
            if let id = self.requestedDiscovery { UserDefaults.standard.set(id,forKey:"last-discovery." + self.mode.rawValue) }
            self.pairingCode = ""; self.phase = .connected; self.lastReceived = ProcessInfo.processInfo.systemUptime
            // Both ends must derive the same default; a Mini may also report a keyboard.
            let candidates = [self.local, identity].sorted {
                if $0.trackpad != $1.trackpad { return $0.trackpad }
                if $0.keyboard != $1.keyboard { return $0.keyboard }
                return $0.id < $1.id
            }
            self.sourceID = candidates[0].id; self.targetID = self.sourceID
            self.savedSelection = self.selectionKey.flatMap { UserDefaults.standard.data(forKey: $0) }
                .flatMap { try? JSONDecoder().decode(SavedSelection.self, from: $0) }
            if let saved = self.savedSelection, self.validSelection(saved.route) {
                self.route = saved.route; self.sourceID = saved.route.source; self.targetID = saved.route.target
            } else { self.savedSelection = nil; self.route = nil }
            self.log.info("Authenticated direct connection established")
            let intent = self.pendingIntent; self.pendingIntent = nil
            if intent == "target" { self.sourceID = self.local.id; self.targetID = identity.id }
            if intent == "source" { self.sourceID = identity.id; self.targetID = self.local.id }
            if intent == "target" || intent == "source" { self.applySelection() }
            // Identity envelopes already tolerate optional route/stamp fields, so older peers
            // can ignore this reconciliation without a wire-protocol change.
            self.session?.send(Message(.identity, identity: self.local,
                route: self.savedSelection?.route, stamp: self.savedSelection?.modifiedAt))
            // Advertise the selection before the receiver sends routeReady. Otherwise a Mac
            // without a saved selection can discard routeReady before learning its token.
            if intent != "target", intent != "source", let saved = self.savedSelection {
                self.acceptRoute(saved.route)
            }
        }
        session.onMessage = { [weak self] message in self?.receive(message) }
        session.onFailure = { [weak self] reason in self?.disconnect("Secure connection: " + reason) }
        session.start()
    }
    func approvePairing() { localPairApproved = true; session?.approve(); detail = text("Waiting for approval on the other Mac", "等待另一台 Mac 确认配对"); connectionBegan = ProcessInfo.processInfo.systemUptime }
    private func validSelection(_ selection: Route) -> Bool {
        guard let peer else { return false }
        return [local.id, peer.id].contains(selection.source) && [local.id, peer.id].contains(selection.target)
    }
    private func rememberSelection(_ selection: Route, modifiedAt: Double? = nil) {
        guard validSelection(selection), let key = selectionKey,
              modifiedAt == nil || modifiedAt?.isFinite == true else { return }
        let revision = modifiedAt ?? max(Date().timeIntervalSince1970, (savedSelection?.modifiedAt ?? 0) + 0.001)
        savedSelection = SavedSelection(route: selection, modifiedAt: revision)
        if let data = try? JSONEncoder().encode(savedSelection) { UserDefaults.standard.set(data, forKey: key) }
    }
    /// Total ordering lets both peers resolve simultaneous selections identically,
    /// including equal wall-clock revisions. Token is the normal tie breaker.
    private func selectionPrecedes(_ lhs: SavedSelection, _ rhs: SavedSelection) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
        if lhs.route.token != rhs.route.token { return lhs.route.token < rhs.route.token }
        if lhs.route.source != rhs.route.source { return lhs.route.source < rhs.route.source }
        return lhs.route.target < rhs.route.target
    }
    private func receiveSelection(_ incoming: Route, revision: Double?) {
        guard validSelection(incoming), revision == nil || revision?.isFinite == true else { return }
        if let revision, let saved = savedSelection,
           selectionPrecedes(SavedSelection(route: incoming, modifiedAt: revision), saved) {
            session?.send(Message(.route, route: saved.route, stamp: saved.modifiedAt)); return
        }
        // Network reconciliation can repeat an already accepted route. Never stop
        // an active or starting source capture merely because its token is echoed.
        if incoming == route {
            if let revision { rememberSelection(incoming, modifiedAt: revision) }
            if incoming.source != incoming.target, incoming.target == local.id {
                guard InputInjector.allowed else { routeFailed("Accessibility permission required", route: incoming); return }
                session?.send(Message(.routeReady, route: incoming))
            }
            return
        }
        rememberSelection(incoming, modifiedAt: revision); acceptRoute(incoming)
    }
    private func applySelection() {
        error = ""
        if sourceID == targetID {
            stopLocalInput(); let route = Route(source: sourceID, target: targetID)
            self.route = route; rememberSelection(route)
            session?.send(Message(.route, route: route, stamp: savedSelection?.modifiedAt)); return
        }
        guard ready, let peer, [local.id, peer.id].contains(sourceID), [local.id, peer.id].contains(targetID) else {
            error = text("Connect and pair the other Mac first.", "请先连接并配对另一台 Mac。"); return
        }
        let route = Route(source: sourceID, target: targetID)
        rememberSelection(route)
        session?.send(Message(.route, route: route, stamp: savedSelection?.modifiedAt)); acceptRoute(route)
    }
    private func acceptRoute(_ route: Route) {
        stopLocalInput()
        guard let peer, [local.id, peer.id].contains(route.source), [local.id, peer.id].contains(route.target) else { return }
        self.route = route; sourceID = route.source; targetID = route.target; error = ""
        guard route.source != route.target else { return }
        if route.target == local.id {
            guard InputInjector.allowed else { routeFailed("Accessibility permission required", route: route); return }
            session?.send(Message(.routeReady, route: route))
        }
    }
    private func receive(_ message: Message) {
        lastReceived = ProcessInfo.processInfo.systemUptime
        capture.renewLease()
        switch message.kind {
        case .identity:
            guard let identity = message.identity, identity.id == peer?.id else { return }
            peer = identity
            if let selection = message.route, let revision = message.stamp {
                receiveSelection(selection, revision: revision)
            }
        case .ping: session?.send(Message(.pong, stamp: message.stamp))
        case .pong:
            if let stamp = message.stamp { latency = max(0, (ProcessInfo.processInfo.systemUptime - stamp) * 1000) }
            if phase == .unstable { phase = .connected }
        case .route:
            if let route = message.route { receiveSelection(route, revision: message.stamp) }
        case .routeReady:
            guard let incoming = message.route, incoming == route, incoming.source == local.id, ready else { return }
            let token = incoming.token
            if forwarding {
                session?.send(Message(.routeActive, route: incoming)); return
            }
            guard captureStartingToken != token else { return }
            captureStartingToken = token
            capture.onInput = { [weak self] packet in
                DispatchQueue.main.async {
                    guard let self, self.forwarding, self.route?.token == token, self.ready else { return }
                    self.session?.send(Message(.input, route: incoming, input: packet))
                }
            }
            capture.gesturesEnabled = gestureForwardingEnabled && peer?.nativeGestureVersion == NativeGestureEvent.version
            capture.start { [weak self] result in
                guard let self, self.captureStartingToken == token else { return }
                self.captureStartingToken = nil
                guard self.route?.token == token, self.ready else { return }
                switch result {
                case .success: self.error = ""; self.forwarding = true; self.session?.send(Message(.routeActive, route: incoming)); self.log.info("Input forwarding started")
                case .failure(let error): self.routeFailed(error.localizedDescription, route: incoming)
                }
            }
        case .routeActive: if message.route == route, route?.target == local.id { error = ""; forwarding = true }
        case .routeError:
            if message.route?.token == route?.token { stopLocalInput(); error = message.detail ?? "Input unavailable"; targetID = sourceID; route = nil }
        case .input:
            guard forwarding, let incoming = message.route, incoming.token == route?.token,
                  route?.target == local.id, route?.source == peer?.id, let packet = message.input else { return }
            guard InputInjector.allowed else { if let route { routeFailed("Accessibility permission was revoked", route: route) }; return }
            injector.apply(packet)
        case .stop:
            stopLocalInput(); route = nil; targetID = sourceID
            rememberSelection(Route(source: sourceID, target: sourceID))
        case .approved: break
        }
    }
    private func routeFailed(_ reason: String, route: Route) {
        stopLocalInput(); error = reason; self.route = nil; targetID = sourceID
        session?.send(Message(.routeError, route: route, detail: reason))
    }
    func stopForwarding() {
        stopLocalInput(); route = nil; targetID = sourceID
        rememberSelection(Route(source: sourceID, target: sourceID))
        session?.send(Message(.stop))
    }
    private func stopLocalInput() { captureStartingToken = nil; capture.stop(); injector.releaseAll(); forwarding = false }
    func disconnect(_ reason: String = "Disconnected") {
        stopLocalInput(); route = nil; targetID = sourceID; phase = .disconnected
        reconnectRequested = false; startupReconnect = false
        session = nil; pairingCode = ""; latency = nil; detail = reason
        let link = self.link; self.link = nil; link?.onClosed = nil; link?.close(reason)
        peer = nil; sourceID = local.id; targetID = local.id
        log.info("Direct connection closed; local input restored")
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastIdentityRefresh >= 2 { refreshIdentity(); lastIdentityRefresh = now }
        if ready {
            let stale = now - lastReceived
            if stale > 1.2 { disconnect("Direct link timed out; input restored locally"); return }
            if stale > 0.65, phase != .unstable {
                stopForwarding(); phase = .unstable
                error = text("Link unstable. Input returned to its source. Retry or choose Bluetooth.", "连接不稳定，输入已返回来源设备。可用鼠标重试或选择蓝牙。")
            }
            session?.send(Message(.ping, stamp: now))
        } else if phase == .connecting, now - connectionBegan > 20 {
            disconnect("Connection timed out")
        } else if phase == .pairing, now - connectionBegan > 180 {
            disconnect("Pairing confirmation timed out")
        }
    }
    private func refreshIdentity() {
        inputPermission = HIDCatalog.allowed; receivePermission = InputInjector.allowed
        // IORegistry enumeration is unnecessary on every heartbeat and can delay input delivery.
        let now = ProcessInfo.processInfo.systemUptime
        var keyboard = local.keyboard, trackpad = local.trackpad
        if !forwarding, now - lastHardwareRefresh >= 10 {
            let endpoints = HIDCatalog.scan(); lastHardwareRefresh = now
            keyboard = endpoints.contains { $0.kind == .keyboard }; trackpad = endpoints.contains { $0.kind == .trackpad }
        }
        let updated = DeviceIdentity(id: local.id, name: IdentityVault.networkName,
            keyboard: keyboard, trackpad: trackpad, canReceive: receivePermission)
        if updated != local { local = updated; session?.send(Message(.identity, identity: updated)) }
        if forwarding, route?.source == local.id, !inputPermission { stopForwarding(); error = "Input Monitoring permission was revoked" }
        Diagnostics.write(store:self)
    }
    func grantInput() {
        HIDCatalog.requestPermission()
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    func grantReceive() {
        InputInjector.requestPermission()
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func forgetPairing() { disconnect("Pairing cleared"); vault?.forgetPeers() }
    func copyDiagnostics() {
        Diagnostics.write(store:self)
        if let text = try? String(contentsOf:Diagnostics.statusFile,encoding:.utf8) {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string)
        }
    }
    func shutdown() { stopped = true; heartbeat?.invalidate(); heartbeat = nil; disconnect("App stopped"); transport?.stop() }
    func quit() { shutdown(); NSApp.terminate(nil) }
    deinit { heartbeat?.invalidate(); capture.stop() }
}
