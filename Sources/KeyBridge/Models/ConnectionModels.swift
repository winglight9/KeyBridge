import Foundation
import KeyBridgeCore

enum LinkMode: String, CaseIterable, Identifiable {
    case wired, bluetooth
    var id: String { rawValue }
}
struct DiscoveredDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

/// All data-link callbacks run on the main queue. The framing is independent of transport.
final class DataLink {
    var onPacket: ((Data) -> Void)?
    var onClosed: ((String) -> Void)?
    var writer: ((Data) -> Void)?
    var closer: (() -> Void)?
    let name: String
    private var decoder = FrameDecoder()
    private(set) var closed = false
    init(name: String) { self.name = name }
    func send(_ data: Data) {
        guard !closed else { return }
        do { writer?(try FrameDecoder.encode(data)) }
        catch { close(error.localizedDescription) }
    }
    func receive(_ data: Data) {
        guard !closed else { return }
        do { for frame in try decoder.append(data) { onPacket?(frame) } }
        catch { close(error.localizedDescription) }
    }
    func close(_ reason: String = "Disconnected") {
        guard !closed else { return }; closed = true
        closer?(); onClosed?(reason)
        writer = nil; closer = nil; onPacket = nil; onClosed = nil
    }
}

protocol BridgeTransport: AnyObject {
    var onDevices: (([DiscoveredDevice]) -> Void)? { get set }
    var onLink: ((DataLink) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    func start()
    func connect(_ id: String)
    func stop()
}
