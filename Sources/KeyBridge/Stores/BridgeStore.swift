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
    @Published private(set) var microphoneSetupMessage = ""
    private var microphoneNeedsConnection = false
    private var microphonePermissionPending = false
    private var microphoneRequestID: String?
    private var stoppedMicrophoneStreams: [String] = []
    private var receiverStarting = false
    private var receiverInstallOffered = false
    private var receiverReloadOffered = false
    var microphoneEnabled: Bool { microphoneState == "sending" || microphoneState == "receiving" }
    var microphonePreparing: Bool { microphoneNeedsConnection || microphoneRequestID != nil || microphoneState == "waiting" || microphoneState == "starting" }
    @Published private(set) var microphoneState = "off"
    @Published private(set) var microphoneError = ""
    @Published private(set) var microphoneDriverAvailable = false
    private var microphoneDriverDetails: [String:Any] = [:]
    private let microphone = MicrophoneCapture()
    private let microphoneReceiver = MicrophoneReceiver()
    private var outgoingMicrophone: String?
    private var incomingMicrophone: String?
    private var microphoneBegan = 0.0
    private var lastMicrophoneFrame = 0.0
    private var receivedMicrophoneFrames = 0
    private var sentMicrophoneFrames = 0
    private var microphoneProbePending = false
    var microphoneActive: Bool { outgoingMicrophone != nil || incomingMicrophone != nil }
    var microphoneCanStart: Bool { ready && phase == .connected && mode == .wired && peer?.microphoneVersion == AudioPacket.version && !microphoneActive }
    var microphoneStatus: String {
        switch microphoneState {
        case "waiting": return text("Preparing microphone…", "正在准备麦克风…")
        case "sending": return text("Microphone → ", "麦克风 → ") + (peer?.name ?? "")
        case "receiving": return text("Receiving microphone from ", "正在接收麦克风：") + (peer?.name ?? "")
        case "muted": return text("Microphone muted", "麦克风已静音")
        case "error": return text("Microphone unavailable", "麦克风暂不可用")
        default: return text("Microphone off", "麦克风已关闭")
        }
    }
    var microphoneDiagnostics: [String: Any] {
        ["state":microphoneState, "driverAvailable":microphoneDriverAvailable, "driver":microphoneDriverDetails,
         "permission":MicrophoneCapture.permissionStatus, "captureRunning":microphone.isRunning,
         "captureCounters":microphone.statistics, "sentFrames":sentMicrophoneFrames,
         "receivedFrames":receivedMicrophoneFrames, "error":microphoneError]
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
        microphoneReceiver.onFailure = { [weak self] stream, reason in
            guard let self, self.incomingMicrophone == stream else { return }
            self.microphoneFailed(reason)
        }
        heartbeat = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        if let heartbeat { RunLoop.main.add(heartbeat, forMode: .common) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.disconnect("Mac is sleeping") })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.shutdown() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.stopMicrophone() })
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
        let continueMicrophoneSetup = microphoneNeedsConnection
        stopMicrophone(send: false)
        if continueMicrophoneSetup { waitForMicrophoneConnection() }
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
        if message.kind.isAudio { receiveMicrophone(message); return }
        switch message.kind {
        case .audioStart, .audioFrame, .audioStop, .audioReady, .audioError, .audioRequest, .audioPreparing, .audioActive: break
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
            capture.nativeKeyboardEnabled = peer?.nativeKeyboardVersion == NativeKeyboardEvent.version
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
        stopMicrophone(send: false); stopLocalInput(); route = nil; targetID = sourceID; phase = .disconnected
        reconnectRequested = false; startupReconnect = false
        session = nil; pairingCode = ""; latency = nil; detail = reason
        let link = self.link; self.link = nil; link?.onClosed = nil; link?.close(reason)
        peer = nil; sourceID = local.id; targetID = local.id
        log.info("Direct connection closed; local input restored")
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastIdentityRefresh >= 2 { refreshIdentity(); lastIdentityRefresh = now }
        if (microphoneState == "waiting" || microphoneState == "starting" || microphoneRequestID != nil), now - microphoneBegan > 600 {
            microphoneFailed(text("Microphone setup timed out. Try again.", "麦克风准备超时，请重试。"))
        }
        if incomingMicrophone != nil, microphoneState == "receiving", now - lastMicrophoneFrame > 1 {
            microphoneFailed(text("Microphone audio stopped arriving.", "麦克风音频已中断。"))
        }
        if ready {
            let stale = now - lastReceived
            if stale > 1.2 { disconnect("Direct link timed out; input restored locally"); return }
            if stale > 0.65, phase != .unstable {
                stopMicrophone(); stopForwarding(); phase = .unstable
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
        if !microphoneProbePending {
            microphoneProbePending = true
            DispatchQueue.global(qos:.utility).async { [weak self] in
                let available = MicrophoneReceiver.available
                let driverDetails = available ? MicrophoneReceiver.diagnostics() : [:]
                DispatchQueue.main.async { guard let self else { return }
                    self.microphoneDriverAvailable = available; self.microphoneDriverDetails = driverDetails; self.microphoneProbePending = false
                    self.advanceMicrophoneSetup() }
            }
        }
        Diagnostics.write(store:self)
    }
    func setMicrophoneEnabled(_ enabled: Bool) {
        if !enabled || microphonePreparing { stopMicrophone(); microphoneError = ""; return }
        microphoneError = ""
        guard mode == .wired else {
            MicrophoneSetupPrompt.show(title:text("Use the wired connection", "麦克风需要有线连接"), message:text("Connect a Thunderbolt cable. Switch to wired mode and continue microphone setup?", "请连接雷雳线。切换到有线模式后继续准备麦克风？"), action:text("Switch to wired", "切换到有线")) { [weak self] accepted in
                guard let self, accepted else { return }
                self.confirmMode = .wired; self.switchMode(); self.waitForMicrophoneConnection()
            }; return
        }
        guard ready, phase == .connected else {
            retry(); waitForMicrophoneConnection(); return
        }
        guard peer?.microphoneVersion == AudioPacket.version else {
            microphoneError = text("Update KeyBridge on both Macs before enabling microphone sharing.", "请先更新两台 Mac 上的键桥，再开启麦克风共享。")
            MicrophoneSetupPrompt.show(title:text("Update the other Mac", "需要更新另一台 Mac"), message:microphoneError, action:text("OK", "知道了")) { _ in }; return
        }
        if sourceID == local.id { startMicrophone() }
        else {
            let id = UUID().uuidString; microphoneRequestID = id
            microphoneBegan = ProcessInfo.processInfo.systemUptime
            microphoneState = "waiting"; microphoneSetupMessage = text("Preparing microphone on ", "正在准备来源麦克风：") + (peer?.name ?? "")
            session?.send(Message(.audioRequest, audio:AudioPacket(streamID:id)))
        }
    }
    private func waitForMicrophoneConnection() {
        microphoneNeedsConnection = true; microphoneState = "waiting"
        microphoneBegan = ProcessInfo.processInfo.systemUptime
        microphoneSetupMessage = text("Connect and pair the other Mac; microphone setup will continue automatically.", "请连接并配对另一台 Mac，就绪后会自动继续准备麦克风。")
    }
    private func advanceMicrophoneSetup() {
        if microphoneNeedsConnection, ready, phase == .connected {
            microphoneNeedsConnection = false; microphoneState = "off"; setMicrophoneEnabled(true); return
        }
        if incomingMicrophone != nil, microphoneState == "waiting", !receiverStarting {
            prepareMicrophoneReceiver()
        }
        if microphonePermissionPending, let id = outgoingMicrophone, MicrophoneCapture.permissionStatus == "authorized" {
            microphonePermissionPending = false; beginMicrophoneCapture(streamID:id)
        }
    }
    private func prepareMicrophoneReceiver() {
        guard let id = incomingMicrophone, !receiverStarting, !microphoneProbePending else { return }
        let compatible = microphoneDriverAvailable && (microphoneDriverDetails["implementationVersion"] as? Int ?? 0) >= 2
        if !compatible {
            let infoPath = "/Library/Audio/Plug-Ins/HAL/KeyBridgeMicrophone.driver/Contents/Info.plist"
            let info = (try? Data(contentsOf:URL(fileURLWithPath:infoPath))).flatMap { try? PropertyListSerialization.propertyList(from:$0, format:nil) as? [String:Any] }
            let installedBuild = Int(info?["CFBundleVersion"] as? String ?? "0") ?? 0
            if installedBuild >= 2 {
                microphoneSetupMessage = text("Waiting for the microphone component to reload…", "等待麦克风组件重新加载…")
                session?.send(Message(.audioPreparing, detail:text("The updated receiving component needs to load on ", "请在接收端完成组件更新并重新加载：") + local.name, audio:AudioPacket(streamID:id)))
                guard !receiverReloadOffered else { return }; receiverReloadOffered = true
                MicrophoneSetupPrompt.show(title:text("Reload the microphone component", "重新加载麦克风组件"), message:text("The component is installed but the loaded copy is out of date. Continue in the system installer to repair and reload only KeyBridge’s virtual microphone. Its audio will briefly pause; the Mac will stay running.", "组件已安装，但当前加载的版本较旧。点击后通过系统安装器修复，并只重新加载键桥的虚拟麦克风；它的音频会短暂中断，电脑保持运行。"), action:text("Reload", "重新加载")) { [weak self] accepted in
                    guard let self, self.incomingMicrophone == id else { return }
                    if accepted { self.openMicrophoneInstaller() } else { self.stopMicrophone() }
                }
                return
            }
            microphoneSetupMessage = text("Waiting for the receiving component update on this Mac…", "等待本机麦克风接收组件更新…")
            session?.send(Message(.audioPreparing, detail:text("Complete the microphone component update on ", "请在接收端完成麦克风组件更新：") + local.name, audio:AudioPacket(streamID:id)))
            guard !receiverInstallOffered else { return }; receiverInstallOffered = true
            MicrophoneSetupPrompt.show(title:text("Install or update the microphone component", "需要安装或更新麦克风组件"), message:text("Approve the receiving component in the system installer. It will reload KeyBridge’s virtual microphone automatically, then setup continues. The virtual microphone may briefly pause; no Mac restart is needed.", "请在系统安装器中批准安装。完成后会自动重新加载键桥的虚拟麦克风并继续准备；虚拟麦克风可能短暂中断，无需重启电脑。"), action:text("Install update", "安装更新")) { [weak self] accepted in
                guard let self, self.incomingMicrophone == id else { return }
                if accepted { self.openMicrophoneInstaller() } else { self.stopMicrophone() }
            }
            return
        }
        receiverStarting = true
        microphoneReceiver.start(streamID:id) { [weak self] failure in
            guard let self, self.incomingMicrophone == id, self.ready else { return }
            if let failure {
                self.microphoneFailed(self.text("Microphone component could not start. ", "麦克风组件启动失败。 ") + failure)
            } else {
                self.microphoneSetupMessage = self.text("Waiting for microphone access on the source Mac…", "等待来源设备授权并发送麦克风音频…")
                self.session?.send(Message(.audioReady, audio:AudioPacket(streamID:id)))
            }
        }
    }
    private func beginMicrophoneCapture(streamID: String) {
        guard outgoingMicrophone == streamID, ready, mode == .wired else { return }
        MicrophoneCapture.requestPermission { [weak self] granted in
            guard let self, self.outgoingMicrophone == streamID, self.ready, self.mode == .wired else { return }
            guard granted else {
                self.microphonePermissionPending = true
                self.microphoneSetupMessage = self.text("Waiting for microphone permission on this Mac…", "等待本机麦克风权限…")
                self.session?.send(Message(.audioPreparing, detail:self.text("Allow microphone access on ", "请在来源设备允许麦克风访问：") + self.local.name, audio:AudioPacket(streamID:streamID)))
                MicrophoneSetupPrompt.show(title:self.text("Allow microphone access", "需要麦克风权限"), message:self.text("Enable KeyBridge in Privacy & Security → Microphone. Setup will continue automatically when permission is available.", "请在“隐私与安全性 → 麦克风”中允许键桥，权限就绪后会自动继续。"), action:self.text("Open Settings", "打开设置")) { [weak self] accepted in
                    guard let self, self.outgoingMicrophone == streamID else { return }
                    if accepted { self.openMicrophonePrivacy() } else { self.stopMicrophone() }
                }
                return
            }
            self.microphone.start(streamID:streamID, onFrame: { [weak self] packet in
                guard let self, self.outgoingMicrophone == streamID, self.ready, self.mode == .wired else { return }
                // Drop stale audio before encryption: queued input packets keep their ordering.
                guard let link = self.link, link.queuedBytes < 8192 else { return }
                self.sentMicrophoneFrames += 1
                self.session?.send(Message(.audioFrame, audio:packet))
            }, onFailure: { [weak self] reason in
                guard let self, self.outgoingMicrophone == streamID else { return }
                self.microphoneFailed(reason)
            }, completion: { [weak self] result in
                guard let self, self.outgoingMicrophone == streamID else { return }
                switch result {
                case .success:
                    self.microphoneState = "starting"
                    self.microphoneSetupMessage = self.text("Waiting for the other Mac to receive audio…", "等待另一台 Mac 确认接收到音频…")
                case .failure(let error): self.microphoneFailed(error.localizedDescription)
                }
            })
        }
    }
    func startMicrophone(streamID: String? = nil) {
        guard microphoneCanStart else { return }
        microphoneError = ""; microphoneState = "waiting"
        microphoneSetupMessage = text("Preparing the receiving Mac…", "正在准备接收端…")
        let id = streamID ?? UUID().uuidString; outgoingMicrophone = id
        microphoneBegan = ProcessInfo.processInfo.systemUptime
        session?.send(Message(.audioStart, audio: AudioPacket(streamID: id)))
    }
    func stopMicrophone(send: Bool = true) {
        let id = outgoingMicrophone ?? incomingMicrophone ?? microphoneRequestID
        if let id { stoppedMicrophoneStreams.append(id); stoppedMicrophoneStreams = Array(stoppedMicrophoneStreams.suffix(32)) }
        outgoingMicrophone = nil; incomingMicrophone = nil; microphoneRequestID = nil
        microphoneNeedsConnection = false; microphonePermissionPending = false
        receiverStarting = false; receiverInstallOffered = false; receiverReloadOffered = false
        microphoneSetupMessage = ""
        microphone.stop(); microphoneReceiver.stop(); microphoneState = "off"
        if send, let id { session?.send(Message(.audioStop, audio: AudioPacket(streamID:id))) }
    }
    func muteMicrophone() {
        guard outgoingMicrophone != nil else { return }
        stopMicrophone(); microphoneState = "muted"
    }
    private func microphoneFailed(_ reason: String, notifyPeer: Bool = true) {
        if notifyPeer, let id = outgoingMicrophone ?? incomingMicrophone ?? microphoneRequestID {
            session?.send(Message(.audioError, detail:reason, audio:AudioPacket(streamID:id)))
        }
        stopMicrophone(); microphoneError = reason; microphoneState = "error"
    }
    func openMicrophoneInstaller() {
        if let url = Bundle.main.url(forResource:"KeyBridge-Microphone", withExtension:"pkg") {
            NSWorkspace.shared.open(url)
        } else {
            microphoneError = text("Download the microphone component from the KeyBridge release page.", "请从键桥发布页下载麦克风组件。")
            NSWorkspace.shared.open(URL(string:"https://github.com/winglight9/KeyBridge/releases/latest")!)
        }
    }
    func openMicrophonePrivacy() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
    private func receiveMicrophone(_ message: Message) {
        guard mode == .wired, ready, let audio = message.audio else { return }
        switch message.kind {
        case .audioStart:
            if stoppedMicrophoneStreams.contains(audio.streamID) {
                session?.send(Message(.audioStop, audio:AudioPacket(streamID:audio.streamID))); return
            }
            guard !microphoneActive else {
                if incomingMicrophone == audio.streamID { return }
                session?.send(Message(.audioError, detail:"Microphone sharing is already active.", audio:AudioPacket(streamID:audio.streamID))); return
            }
            microphoneRequestID = nil
            incomingMicrophone = audio.streamID; microphoneState = "waiting"; microphoneError = ""
            microphoneBegan = ProcessInfo.processInfo.systemUptime
            prepareMicrophoneReceiver()
        case .audioRequest:
            if stoppedMicrophoneStreams.contains(audio.streamID) {
                session?.send(Message(.audioStop, audio:AudioPacket(streamID:audio.streamID))); return
            }
            guard !microphoneActive, sourceID == local.id else {
                session?.send(Message(.audioError, detail:text("Choose this Mac as the microphone source first.", "请先将来源设备选择为这台 Mac。"), audio:AudioPacket(streamID:audio.streamID))); return
            }
            startMicrophone(streamID:audio.streamID)
        case .audioPreparing:
            if outgoingMicrophone == audio.streamID || incomingMicrophone == audio.streamID || microphoneRequestID == audio.streamID {
                microphoneSetupMessage = message.detail ?? text("Preparing the other Mac…", "正在准备另一台 Mac…")
            }
        case .audioActive:
            if outgoingMicrophone == audio.streamID, microphone.isRunning { microphoneState = "sending"; microphoneSetupMessage = "" }
        case .audioReady:
            guard outgoingMicrophone == audio.streamID, microphoneState == "waiting" else { return }
            beginMicrophoneCapture(streamID:audio.streamID)
        case .audioFrame:
            guard incomingMicrophone == audio.streamID, let pcm = audio.pcm else { return }
            lastMicrophoneFrame = ProcessInfo.processInfo.systemUptime
            receivedMicrophoneFrames += 1
            microphoneReceiver.push(pcm) { [weak self] in
                guard let self, self.incomingMicrophone == audio.streamID, self.microphoneState != "receiving" else { return }
                self.microphoneState = "receiving"; self.microphoneSetupMessage = ""
                self.session?.send(Message(.audioActive, audio:AudioPacket(streamID:audio.streamID)))
            }
        case .audioStop:
            stoppedMicrophoneStreams.append(audio.streamID); stoppedMicrophoneStreams = Array(stoppedMicrophoneStreams.suffix(32))
            if outgoingMicrophone == audio.streamID || incomingMicrophone == audio.streamID || microphoneRequestID == audio.streamID { stopMicrophone(send:false) }
        case .audioError:
            if outgoingMicrophone == audio.streamID || incomingMicrophone == audio.streamID || microphoneRequestID == audio.streamID {
                microphoneFailed(text("Microphone setup failed on ", "对方麦克风准备失败：") + (peer?.name ?? "") + ". " + (message.detail ?? ""), notifyPeer:false)
            }
        default: break
        }
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
