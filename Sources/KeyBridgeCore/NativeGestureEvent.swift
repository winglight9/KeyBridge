import Foundation
import CoreGraphics

/// Opaque Quartz native-input transport, not a table mapping gestures to actions.
///
/// Preserve interpreted gesture streams (29/30) and the original continuous scroll
/// event. Reconstructing scroll values loses whether macOS already applied the
/// source Mac's natural-scroll direction, which can reverse the destination result.
/// The destination interprets the payload; availability still requires device testing.
public enum NativeGestureEvent {
    public static let version = 3
    public static let eventType: UInt32 = 29
    public static let dockEventType: UInt32 = 30
    public static let scrollEventType = CGEventType.scrollWheel.rawValue
    public static let eventTypes: Set<UInt32> = [eventType, dockEventType, scrollEventType]
    public static let maximumBytes = 16_384
    /// Tags our own replay, so it can never be captured and bounced back to the peer.
    public static let replayMarker: Int64 = 0x4B425247455354
    // Quartz's gesture-phase field is not in the public CGEventField enum.
    // Its 0x84 value is also used by Hammerspoon TouchEvents.c; no upstream code is bundled.
    private static let phaseField = CGEventField(rawValue: 0x84)!

    public static func isGesture(_ event: CGEvent) -> Bool { eventTypes.contains(event.type.rawValue) }
    public static func isInterpretedGesture(_ event: CGEvent) -> Bool {
        event.type.rawValue == eventType || event.type.rawValue == dockEventType
    }
    public static func isScroll(_ event: CGEvent) -> Bool { event.type == .scrollWheel }

    public static func encode(_ event: CGEvent) -> InputPacket? {
        guard isGesture(event), event.getIntegerValueField(.eventSourceUserData) != replayMarker,
              let flattened = event.data else { return nil }
        let bytes = flattened as Data
        guard !bytes.isEmpty, bytes.count <= maximumBytes else { return nil }
        return InputPacket(.gesture, code:Int(event.type.rawValue), nativeEvent:bytes)
    }

    public static func decode(_ bytes: Data) -> CGEvent? {
        guard !bytes.isEmpty, bytes.count <= maximumBytes,
              let event = CGEvent(withDataAllocator:nil, data:bytes as CFData), isGesture(event) else { return nil }
        return event
    }

    /// Reset machine-local routing metadata while retaining gesture subtype, contacts,
    /// phase, magnification, rotation and every other gesture field in the payload.
    public static func prepareForReplay(_ event: CGEvent, source: CGEventSource?, at point: CGPoint, timestamp: UInt64) {
        event.setSource(source)
        // Process identifiers from the sender have no meaning on the receiving Mac.
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 0)
        event.setIntegerValueField(.eventTargetProcessSerialNumber, value: 0)
        event.location = point
        event.timestamp = timestamp
        event.setIntegerValueField(.eventSourceUserData,value:replayMarker)
    }

    public static func isComplete(_ event: CGEvent) -> Bool {
        guard isInterpretedGesture(event) else { return true }
        return event.getIntegerValueField(phaseField) & 0x0C != 0 // ended or cancelled
    }

    /// A stopped route must not leave the target in an ongoing native gesture.
    /// This is a cancellation phase of the same gesture, never an application action.
    public static func cancelledCopy(of event: CGEvent) -> CGEvent? {
        guard isInterpretedGesture(event), let copy = event.copy() else { return nil }
        copy.setIntegerValueField(phaseField,value:8)
        return copy
    }
}
