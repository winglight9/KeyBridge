import Foundation
import CoreBluetooth

final class BluetoothTransport: NSObject, BridgeTransport, CBCentralManagerDelegate, CBPeripheralManagerDelegate, CBPeripheralDelegate {
    static let serviceID = CBUUID(string: "8B1909B4-CE0C-41CD-81FC-B943CD492E5A")
    static let streamID = CBUUID(string: "634A25C5-73C8-4AD6-B9F6-F1C77E907B42")
    var onDevices: (([DiscoveredDevice]) -> Void)?
    var onLink: ((DataLink) -> Void)?
    var onStatus: ((String) -> Void)?
    private var central: CBCentralManager?
    private var server: CBPeripheralManager?
    private var localStream: CBMutableCharacteristic?
    private var peers: [String: CBPeripheral] = [:]
    private var names: [String: String] = [:]
    private var selected: CBPeripheral?
    private var remoteStream: CBCharacteristic?
    private var subscriber: CBCentral?
    private var link: DataLink?
    private var queue: [Data] = []
    private var queuedBytes = 0
    private var isCentral = false
    private var running = false
    private var earlyNotifications: [Data] = []

    func start() {
        stop(); running = true
        central = CBCentralManager(delegate: self, queue: nil)
        server = CBPeripheralManager(delegate: self, queue: nil)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard running else { return }
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [Self.serviceID], options: [CBCentralManagerScanOptionAllowDuplicatesKey:false])
            onStatus?("Discovering Bluetooth devices")
        } else { onStatus?(stateDescription(central.state)); link?.close("Bluetooth unavailable") }
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard running else { return }
        if peripheral.state == .poweredOn {
            let stream = CBMutableCharacteristic(type: Self.streamID, properties: [.write, .writeWithoutResponse, .notify], value: nil, permissions: [.writeable])
            localStream = stream
            let service = CBMutableService(type: Self.serviceID, primary: true); service.characteristics = [stream]
            peripheral.add(service)
        } else { onStatus?(stateDescription(peripheral.state)); link?.close("Bluetooth unavailable") }
    }
    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unauthorized: return "Bluetooth permission required"
        case .poweredOff: return "Bluetooth is off"
        case .unsupported: return "Bluetooth is unsupported"
        case .resetting: return "Bluetooth is resetting"
        default: return "Bluetooth is starting"
        }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard running else { return }
        if let error { onStatus?(error.localizedDescription); return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey:[Self.serviceID], CBAdvertisementDataLocalNameKey:IdentityVault.networkName])
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard running else { return }
        let id = peripheral.identifier.uuidString
        peers[id] = peripheral
        names[id] = UserDefaults.standard.string(forKey:"bluetooth-name." + id) ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Nearby Mac · " + String(id.suffix(4))
        onDevices?(names.map { DiscoveredDevice(id: $0.key, name: $0.value) }.sorted { $0.name < $1.name })
    }
    func connect(_ id: String) {
        guard running, central?.state == .poweredOn, let peripheral = peers[id] else { onStatus?("Bluetooth device is unavailable"); return }
        link?.close("Replaced connection"); link = nil; queue.removeAll(); queuedBytes = 0
        selected = peripheral; isCentral = true; peripheral.delegate = self
        central?.connect(peripheral, options: nil); onStatus?("Connecting Bluetooth")
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard running, peripheral == selected else { central.cancelPeripheralConnection(peripheral); return }
        peripheral.discoverServices([Self.serviceID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onStatus?(error?.localizedDescription ?? "Bluetooth connection failed")
        link?.close("Bluetooth connection failed")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == selected else { return }
        link?.close(error?.localizedDescription ?? "Bluetooth disconnected"); selected = nil; remoteStream = nil
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { onStatus?(error.localizedDescription); return }
        for service in peripheral.services ?? [] where service.uuid == Self.serviceID { peripheral.discoverCharacteristics([Self.streamID], for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { onStatus?(error.localizedDescription); return }
        if let characteristic = service.characteristics?.first(where: { $0.uuid == Self.streamID }) {
            remoteStream = characteristic; peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard running, peripheral == selected, characteristic == remoteStream else { return }
        if let error { onStatus?(error.localizedDescription); return }
        guard characteristic.isNotifying else { link?.close("Bluetooth notifications unavailable"); return }
        let link = DataLink(name: names[peripheral.identifier.uuidString] ?? "Bluetooth Mac")
        self.link = link; isCentral = true
        link.writer = { [weak self] data in self?.enqueue(data, mtu: peripheral.maximumWriteValueLength(for: .withoutResponse)) }
        link.closer = { [weak self, weak peripheral] in if let peripheral { self?.central?.cancelPeripheralConnection(peripheral) }; self?.clearQueue() }
        onLink?(link)
        let early = earlyNotifications; earlyNotifications.removeAll()
        for data in early { link.receive(data) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == selected else { return }
        if let error { link?.close(error.localizedDescription); return }
        if let data = characteristic.value {
            if let link, !link.closed { link.receive(data) }
            else if earlyNotifications.reduce(0, { $0 + $1.count }) + data.count <= 65_540 { earlyNotifications.append(data) }
            else { central?.cancelPeripheralConnection(peripheral) }
        }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { pump() }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard running, characteristic.uuid == Self.streamID else { return }
        guard link == nil || link?.closed == true else { return }
        subscriber = central; isCentral = false
        peripheral.setDesiredConnectionLatency(.low, for:central)
        let link = DataLink(name: "Bluetooth Mac"); self.link = link
        link.writer = { [weak self] data in self?.enqueue(data, mtu: central.maximumUpdateValueLength) }
        link.closer = { [weak self] in self?.subscriber = nil; self?.clearQueue() }
        onLink?(link)
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if central.identifier == subscriber?.identifier { link?.close("Bluetooth peer disconnected"); subscriber = nil }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard running, request.characteristic.uuid == Self.streamID, request.central.identifier == subscriber?.identifier, request.offset == 0, let value = request.value else {
                peripheral.respond(to: request, withResult: .writeNotPermitted); continue
            }
            peripheral.respond(to: request, withResult: .success); link?.receive(value)
        }
    }
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) { pump() }
    private func enqueue(_ data: Data, mtu: Int) {
        guard mtu > 0, queuedBytes + data.count < 131_072 else { link?.close("Bluetooth send queue full"); return }
        var offset = 0
        while offset < data.count {
            let end = min(data.count, offset + mtu)
            queue.append(Data(data[offset..<end])); offset = end
        }
        queuedBytes += data.count; pump()
    }
    private func pump() {
        while let data = queue.first, link?.closed == false {
            if isCentral {
                guard let selected, let remoteStream, selected.canSendWriteWithoutResponse else { return }
                selected.writeValue(data, for: remoteStream, type: .withoutResponse)
            } else {
                guard let server, let localStream, let subscriber,
                      server.updateValue(data, for: localStream, onSubscribedCentrals: [subscriber]) else { return }
            }
            queue.removeFirst(); queuedBytes -= data.count
        }
    }
    private func clearQueue() { queue.removeAll(); queuedBytes = 0; earlyNotifications.removeAll() }
    @discardableResult func rememberName(_ name:String) -> String? {
        if let id = selected?.identifier.uuidString ?? subscriber?.identifier.uuidString {
            UserDefaults.standard.set(name,forKey:"bluetooth-name." + id); names[id] = name
            onDevices?(names.map { DiscoveredDevice(id:$0.key,name:$0.value) }.sorted { $0.name < $1.name })
            return id
        }
        return nil
    }
    func stop() {
        running = false
        link?.close(); link = nil
        if let selected { central?.cancelPeripheralConnection(selected) }
        central?.stopScan(); server?.stopAdvertising(); server?.removeAllServices()
        selected = nil; subscriber = nil; remoteStream = nil; localStream = nil
        peers.removeAll(); names.removeAll(); clearQueue(); onDevices?([])
        central = nil; server = nil
    }
}
