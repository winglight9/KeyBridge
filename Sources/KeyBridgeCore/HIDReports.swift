import Foundation

/// USB HID keyboard usage -> macOS virtual key code. No characters or input text are stored.
public enum KeyboardUsage {
    public static let keyCode: [Int: Int] = [
        4:0,5:11,6:8,7:2,8:14,9:3,10:5,11:4,12:34,13:38,14:40,15:37,16:46,
        17:45,18:31,19:35,20:12,21:15,22:1,23:17,24:32,25:9,26:13,27:7,28:16,29:6,
        30:18,31:19,32:20,33:21,34:23,35:22,36:26,37:28,38:25,39:29,
        40:36,41:53,42:51,43:48,44:49,45:27,46:24,47:33,48:30,49:42,50:10,51:41,52:39,53:50,54:43,55:47,56:44,57:57,
        58:122,59:120,60:99,61:118,62:96,63:97,64:98,65:100,66:101,67:109,68:103,69:111,
        70:105,71:107,72:113,73:114,74:115,75:116,76:117,77:119,78:121,79:124,80:123,81:125,82:126,
        83:71,84:75,85:67,86:78,87:69,88:76,89:83,90:84,91:85,92:86,93:87,94:88,95:89,96:91,97:92,98:82,99:65,
        100:10,103:81,104:105,105:107,106:113,107:106,108:64,109:79,110:80,111:90,
        135:94,137:93,144:104,145:102,
        224:59,225:56,226:58,227:55,228:62,229:60,230:61,231:54
    ]
    public static func modifierFlags(_ pressed: Set<Int>, capsLock: Bool) -> UInt64 {
        var flags: UInt64 = capsLock ? 1 << 16 : 0
        if !pressed.isDisjoint(with: [225,229]) { flags |= 1 << 17 }
        if !pressed.isDisjoint(with: [224,228]) { flags |= 1 << 18 }
        if !pressed.isDisjoint(with: [226,230]) { flags |= 1 << 19 }
        if !pressed.isDisjoint(with: [227,231]) { flags |= 1 << 20 }
        return flags
    }
}

public struct KeyboardReportDecoder {
    public private(set) var pressed = Set<Int>()
    private var capsLock = false
    public init(capsLock: Bool = false) { self.capsLock = capsLock }
    public mutating func decode(_ bytes: [UInt8], reportID: Int) throws -> [InputPacket] {
        let offset: Int
        if bytes.count >= 9 && bytes[0] == 1 { offset = 1 }
        else if bytes.count == 8 { offset = 0 }
        else { throw BridgeError.invalid("Unsupported keyboard report") }
        let keys = bytes[(offset + 2)..<(offset + 8)]
        guard !keys.contains(where: { (1...3).contains($0) }) else { return [] } // HID rollover; wait for a complete report.
        var now = Set(keys.filter { $0 > 3 }.map(Int.init))
        for bit in 0..<8 where bytes[offset] & (1 << bit) != 0 { now.insert(224 + bit) }
        if now.contains(57), !pressed.contains(57) { capsLock.toggle() }
        let flags = KeyboardUsage.modifierFlags(now, capsLock: capsLock)
        let released = pressed.subtracting(now).sorted()
        let added = now.subtracting(pressed).sorted()
        pressed = now
        return released.compactMap { u in KeyboardUsage.keyCode[u].map { InputPacket(.key, code: $0, down: false, flags: flags) } } +
               added.compactMap { u in KeyboardUsage.keyCode[u].map { InputPacket(.key, code: $0, down: true, flags: flags) } }
    }
}

public struct TrackpadContact: Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
public struct TrackpadFrame {
    public var contacts: [TrackpadContact]
    public var pressed: Bool
    public init(contacts: [TrackpadContact], pressed: Bool) { self.contacts = contacts; self.pressed = pressed }
}

/// Apple SPI report facts: 8-byte mouse prefix, 38-byte touch header, 30-byte contacts.
/// Protocol reference: Asahi Linux hid-magicmouse.c (see docs/architecture.md).
/// This parser never opens, reads, or translates an external mouse.
public enum AppleTrackpadReport {
    public static func decode(_ bytes: [UInt8]) throws -> TrackpadFrame {
        guard bytes.count >= 46, bytes[0] == 2 else { throw BridgeError.invalid("Unsupported Apple SPI trackpad report") }
        let count = Int(bytes[30])
        guard count <= 16, bytes.count >= 46 + count * 30 else { throw BridgeError.invalid("Truncated trackpad report") }
        func signed(_ offset: Int) -> Int16 { Int16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8) }
        var contacts: [TrackpadContact] = []
        for index in 0..<count {
            let offset = 46 + index * 30
            guard signed(offset + 18) > 0 else { continue }
            contacts.append(TrackpadContact(x: Double(signed(offset + 4)), y: -Double(signed(offset + 6))))
        }
        return TrackpadFrame(contacts: contacts, pressed: bytes[31] & 1 != 0)
    }
}

public struct TrackpadInterpreter {
    private var previous: TrackpadContact?
    private var fingers = 0
    private var button: Int?
    private var touchStart: Double = 0
    private var travel: Double = 0
    private var clicked = false
    public var pointerGain: Double = 0.12
    public var scrollGain: Double = 0.045
    public init() {}
    public mutating func consume(_ frame: TrackpadFrame, time: Double) -> [InputPacket] {
        var events: [InputPacket] = []
        let count = frame.contacts.count
        let center: TrackpadContact? = count > 0 ? TrackpadContact(
            x: frame.contacts.map(\.x).reduce(0,+) / Double(count),
            y: frame.contacts.map(\.y).reduce(0,+) / Double(count)) : nil
        if fingers == 0, count > 0 { touchStart = time; travel = 0; clicked = false }
        if let center, let previous, count == fingers, count <= 2 {
            let dx = center.x - previous.x, dy = center.y - previous.y
            travel += abs(dx) + abs(dy)
            if abs(dx) < 2000, abs(dy) < 2000 {
                if count == 1 { events.append(InputPacket(.move, dx: dx * pointerGain, dy: dy * pointerGain)) }
                else if count == 2 { events.append(InputPacket(.scroll, dx: -dx * scrollGain, dy: -dy * scrollGain)) }
            }
        }
        if frame.pressed, button == nil {
            let code = count >= 2 ? 1 : 0
            button = code; clicked = true; events.append(InputPacket(.button, code: code, down: true))
        } else if !frame.pressed, let code = button {
            button = nil; events.append(InputPacket(.button, code: code, down: false))
        }
        if count == 0, (1...2).contains(fingers), !clicked, time - touchStart < 0.19, travel < 100 {
            let code = fingers == 2 ? 1 : 0
            events += [InputPacket(.button, code: code, down: true), InputPacket(.button, code: code, down: false)]
        }
        previous = center; fingers = count
        return events
    }
}
