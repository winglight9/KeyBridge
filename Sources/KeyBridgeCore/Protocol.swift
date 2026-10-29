import Foundation

public struct DeviceIdentity: Codable, Equatable {
    public var id: String
    public var name: String
    public var keyboard: Bool
    public var trackpad: Bool
    public var canReceive: Bool
    /// Absent in older peers; never send opaque gesture packets unless both ends support them.
    public var nativeGestureVersion: Int?
    public init(id: String, name: String, keyboard: Bool, trackpad: Bool, canReceive: Bool, nativeGestureVersion: Int? = NativeGestureEvent.version) {
        self.id = id; self.name = name; self.keyboard = keyboard
        self.trackpad = trackpad; self.canReceive = canReceive
        self.nativeGestureVersion = nativeGestureVersion
    }
}

public struct InputPacket: Codable, Equatable {
    public enum Kind: String, Codable { case key, move, button, scroll, gesture }
    public var kind: Kind
    public var code: Int
    public var down: Bool
    public var dx: Double
    public var dy: Double
    public var flags: UInt64
    public var isRepeat: Bool
    public var nativeEvent: Data?
    public init(_ kind: Kind, code: Int = 0, down: Bool = false, dx: Double = 0, dy: Double = 0, flags: UInt64 = 0, isRepeat: Bool = false, nativeEvent: Data? = nil) {
        self.kind = kind; self.code = code; self.down = down
        self.dx = dx; self.dy = dy; self.flags = flags; self.isRepeat = isRepeat
        self.nativeEvent = nativeEvent
    }
    public var isValid: Bool {
        guard dx.isFinite && dy.isFinite && abs(dx) <= 4096 && abs(dy) <= 4096 &&
        (kind != .key || (0...127).contains(code)) &&
        (kind != .button || (0...2).contains(code)) else { return false }
        if kind == .gesture {
            guard NativeGestureEvent.eventTypes.contains(UInt32(clamping:code)), !down, !isRepeat, dx == 0, dy == 0,
                  let nativeEvent else { return false }
            return NativeGestureEvent.decode(nativeEvent)?.type.rawValue == UInt32(clamping:code)
        }
        return nativeEvent == nil
    }
}

public struct Route: Codable, Equatable {
    public var source: String
    public var target: String
    public var token: String
    public init(source: String, target: String, token: String = UUID().uuidString) {
        self.source = source; self.target = target; self.token = token
    }
}

public struct Message: Codable {
    public enum Kind: String, Codable { case approved, identity, route, routeReady, routeActive, routeError, input, stop, ping, pong }
    public var kind: Kind
    public var identity: DeviceIdentity?
    public var route: Route?
    public var input: InputPacket?
    public var detail: String?
    public var stamp: Double?
    public init(_ kind: Kind, identity: DeviceIdentity? = nil, route: Route? = nil, input: InputPacket? = nil, detail: String? = nil, stamp: Double? = nil) {
        self.kind = kind; self.identity = identity; self.route = route
        self.input = input; self.detail = detail; self.stamp = stamp
    }
}

public enum BridgeError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

/// The same bounded framing is used for TCP and fragmented BLE writes/notifications.
public struct FrameDecoder {
    public static let maximum = 65_536
    private var buffer = Data()
    public init() {}
    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= maximum else { throw BridgeError.invalid("Frame too large") }
        var size = UInt32(payload.count).bigEndian
        var result = withUnsafeBytes(of: &size) { Data($0) }
        result.append(payload); return result
    }
    public mutating func append(_ data: Data) throws -> [Data] {
        guard data.count <= Self.maximum + 4, buffer.count + data.count <= Self.maximum * 2 + 8 else {
            throw BridgeError.invalid("Input buffer overflow")
        }
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let size = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard size > 0 && size <= Self.maximum else { throw BridgeError.invalid("Invalid frame length") }
            guard buffer.count >= size + 4 else { break }
            frames.append(Data(buffer.dropFirst(4).prefix(size)))
            buffer.removeFirst(size + 4)
        }
        return frames
    }
}
