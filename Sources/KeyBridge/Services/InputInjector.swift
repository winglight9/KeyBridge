import AppKit
import ApplicationServices
import KeyBridgeCore

final class InputInjector {
    private var keys = Set<Int>()
    private var buttons = Set<Int>()
    private let source = CGEventSource(stateID: .privateState)
    private var scrollX = 0.0, scrollY = 0.0
    private var lastClick = 0.0
    private var lastPoint = CGPoint.zero
    private var clickCount: Int64 = 1
    private var flags = CGEventFlags()
    private var lastNativeGestures: [UInt32:CGEvent] = [:]
    private var cursor: CGPoint?
    private var postedPositions: [CGPoint] = []
    private var lastMoveAt = 0.0
    private var displayBounds: [CGRect] = []
    private var displayBoundsAt = 0.0
    private(set) var statistics: [String:Int] = [:]
    static var allowed: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func apply(_ packet: InputPacket) {
        guard Self.allowed, packet.isValid else { return }
        statistics[packet.kind.rawValue, default: 0] += 1
        switch packet.kind {
        case .key:
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(packet.code), keyDown: packet.down) else { return }
            if [54,55,56,57,58,59,60,61,62].contains(packet.code) { event.type = .flagsChanged }
            flags = CGEventFlags(rawValue: packet.flags); event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: packet.isRepeat ? 1 : 0)
            if packet.down { keys.insert(packet.code) } else { keys.remove(packet.code) }
            event.post(tap: .cghidEventTap)
        case .move:
            let old = currentPointer()
            let point = clamp(CGPoint(x: old.x + packet.dx, y: old.y + packet.dy))
            cursor = point; lastMoveAt = ProcessInfo.processInfo.systemUptime
            postedPositions.append(point)
            if postedPositions.count > 64 { postedPositions.removeFirst(postedPositions.count - 64) }
            let type: CGEventType = buttons.contains(0) ? .leftMouseDragged : buttons.contains(1) ? .rightMouseDragged : .mouseMoved
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: buttons.contains(1) ? .right : .left)
            event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(packet.dx.rounded()))
            event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(packet.dy.rounded()))
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        case .button:
            let point = currentPointer()
            let type: CGEventType = packet.code == 1 ? (packet.down ? .rightMouseDown : .rightMouseUp) : (packet.down ? .leftMouseDown : .leftMouseUp)
            if packet.down {
                let now = ProcessInfo.processInfo.systemUptime
                clickCount = now - lastClick < NSEvent.doubleClickInterval && hypot(point.x-lastPoint.x, point.y-lastPoint.y) < 5 ? min(3, clickCount + 1) : 1
                lastClick = now; lastPoint = point; buttons.insert(packet.code)
            } else { buttons.remove(packet.code) }
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: packet.code == 1 ? .right : .left)
            event?.flags = flags; event?.setIntegerValueField(.mouseEventClickState, value: clickCount); event?.post(tap: .cghidEventTap)
        case .scroll:
            scrollX += packet.dx; scrollY += packet.dy
            let x = Int32(scrollX), y = Int32(scrollY); scrollX -= Double(x); scrollY -= Double(y)
            guard x != 0 || y != 0 else { return }
            let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)
            event?.flags = flags; event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1); event?.post(tap: .cghidEventTap)
        case .gesture:
            guard let bytes = packet.nativeEvent, let event = NativeGestureEvent.decode(bytes) else { return }
            statistics["gestureAppKitType" + String(NSEvent(cgEvent:event)?.type.rawValue ?? 0), default:0] += 1
            postNativeGesture(event)
            statistics["gestureQuartzType" + String(event.type.rawValue), default:0] += 1
            lastNativeGestures[event.type.rawValue] = NativeGestureEvent.isComplete(event) ? nil : event
        }
    }
    func releaseAll() {
        if Self.allowed {
            for type in lastNativeGestures.keys.sorted() {
                if let event = lastNativeGestures[type], let cancellation = NativeGestureEvent.cancelledCopy(of:event) {
                    postNativeGesture(cancellation)
                }
            }
        }
        lastNativeGestures.removeAll()
        for key in keys.sorted() { apply(InputPacket(.key, code: key, down: false)) }
        for button in buttons.sorted() { apply(InputPacket(.button, code: button, down: false)) }
        keys.removeAll(); buttons.removeAll(); scrollX = 0; scrollY = 0; flags = []
        cursor = nil; postedPositions.removeAll(); lastMoveAt = 0
    }
    private func postNativeGesture(_ event: CGEvent) {
        let current = CGEvent(source:nil)
        NativeGestureEvent.prepareForReplay(event,source:source,at:current?.location ?? .zero,timestamp:current?.timestamp ?? 0)
        // Quartz gesture payloads are already interpreted events; replay at the session layer.
        event.post(tap:.cgSessionEventTap)
        statistics["gesturePosted", default:0] += 1
    }
    private func currentPointer() -> CGPoint {
        let actual = CGEvent(source:nil)?.location ?? cursor ?? .zero
        let now = ProcessInfo.processInfo.systemUptime
        // CGEvent.post is asynchronous. Do not restart each delta from a stale cursor sample.
        // A position outside our recent posts belongs to the independent local mouse.
        let ourPosition = postedPositions.contains { hypot($0.x-actual.x, $0.y-actual.y) < 1 }
        if cursor == nil || now-lastMoveAt > 0.1 || !ourPosition {
            cursor = actual; postedPositions = [actual]
        }
        return cursor ?? actual
    }
    private func clamp(_ point: CGPoint) -> CGPoint {
        let now = ProcessInfo.processInfo.systemUptime
        if displayBounds.isEmpty || now-displayBoundsAt >= 2 { refreshDisplayBounds(); displayBoundsAt = now }
        let bounds = displayBounds
        if bounds.contains(where: { $0.contains(point) }) { return point }
        return bounds.map { rect in CGPoint(x: max(rect.minX, min(rect.maxX - 1, point.x)), y: max(rect.minY, min(rect.maxY - 1, point.y))) }
            .min { hypot($0.x-point.x,$0.y-point.y) < hypot($1.x-point.x,$1.y-point.y) } ?? point
    }
    private func refreshDisplayBounds() {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32); var count: UInt32 = 0
        guard CGGetActiveDisplayList(32, &displays, &count) == .success else { return }
        displayBounds = displays.prefix(Int(count)).map(CGDisplayBounds)
    }
}
