import AppKit
import CoreGraphics
import Foundation

/// Non-text keyboard events retain their native type, flags and hardware fields.
/// No mapping to a dictation, WeChat, or other application shortcut is performed.
public enum NativeKeyboardEvent {
    public static let version = 1
    public static let systemType: UInt32 = 14
    public static let maximumBytes = 4096
    public static func accepts(_ event: CGEvent) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        switch event.type {
        case .flagsChanged: return code == 63
        case .keyDown, .keyUp: return (128...255).contains(code)
        default:
            guard event.type.rawValue == systemType, let ns = NSEvent(cgEvent:event), ns.type == .systemDefined,
                  ns.subtype.rawValue == 8 else { return false }
            let key = (ns.data1 >> 16) & 0xffff, state = (ns.data1 >> 8) & 0xff
            // Power-key handling stays with its physical Mac.
            return key != 6 && (0...255).contains(key) && (state == 10 || state == 11)
        }
    }
    public static func encode(_ event: CGEvent) -> InputPacket? {
        guard accepts(event), let data = event.data, CFDataGetLength(data) <= maximumBytes else { return nil }
        return InputPacket(.nativeKey, code:Int(event.type.rawValue), nativeEvent:data as Data)
    }
    public static func decode(_ data: Data) -> CGEvent? {
        guard !data.isEmpty, data.count <= maximumBytes,
              let event = CGEvent(withDataAllocator:nil, data:data as CFData), accepts(event) else { return nil }
        return event
    }
    public static func key(_ event: CGEvent) -> Int {
        if event.type.rawValue == systemType { return 0x10000 | (((NSEvent(cgEvent:event)?.data1 ?? 0) >> 16) & 0xffff) }
        return Int(event.getIntegerValueField(.keyboardEventKeycode))
    }
    public static func isDown(_ event: CGEvent) -> Bool {
        if event.type == .flagsChanged { return event.flags.contains(.maskSecondaryFn) }
        if event.type.rawValue == systemType { return ((NSEvent(cgEvent:event)?.data1 ?? 0) >> 8) & 0xff == 10 }
        return event.type == .keyDown
    }
    public static func releasedCopy(_ event: CGEvent) -> CGEvent? {
        if event.type.rawValue == systemType, let ns = NSEvent(cgEvent:event) {
            return NSEvent.otherEvent(with:.systemDefined, location:.zero, modifierFlags:[], timestamp:0,
                windowNumber:0, context:nil, subtype:8,
                data1:((ns.data1 >> 16) & 0xffff) << 16 | 0x0b00, data2:ns.data2)?.cgEvent
        }
        guard let copy = event.copy() else { return nil }
        if copy.type == .flagsChanged { copy.flags.remove(.maskSecondaryFn) } else { copy.type = .keyUp }
        return copy
    }
}
