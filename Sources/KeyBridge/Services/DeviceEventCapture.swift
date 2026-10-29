import AppKit
import Foundation
import CoreGraphics
import ApplicationServices
import IOKit
import Darwin
import KeyBridgeCore

/// macOS has no public Quartz field for a physical mouse/trackpad sender.
/// Resolve the system's optional IOHID copy accessor at runtime and fail closed if unavailable.
/// Unknown senders stay local. A sender ID alone does not prove an event was
/// never copied or synthesized by another application.
private final class PhysicalEventSource {
    typealias CopyEvent = @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer?
    typealias SenderID = @convention(c) (UnsafeRawPointer) -> UInt64
    typealias Children = @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer?
    private var handles: [UnsafeMutableRawPointer] = []
    private let copy: CopyEvent
    private let sender: SenderID
    private let children: Children?
    init() throws {
        guard let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",RTLD_LAZY),
              let io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_LAZY) else { throw BridgeError.invalid("Physical input identification unavailable") }
        handles = [cg,io]
        guard let c = dlsym(cg,"CGEventCopyIOHIDEvent"), let s = dlsym(io,"IOHIDEventGetSenderID") else {
            throw BridgeError.invalid("Physical input identification unavailable")
        }
        copy = unsafeBitCast(c,to:CopyEvent.self); sender = unsafeBitCast(s,to:SenderID.self)
        if let p = dlsym(io,"IOHIDEventGetChildren") { children = unsafeBitCast(p,to:Children.self) } else { children = nil }
    }
    func identifiers(_ event: CGEvent) -> Set<UInt64> {
        guard let hid = copy(Unmanaged.passUnretained(event).toOpaque()) else { return [] }
        defer { Unmanaged<CFTypeRef>.fromOpaque(hid).release() }
        var values = Set<UInt64>()
        func visit(_ object: UnsafeRawPointer, depth:Int) {
            let id = sender(object); if id != 0 { values.insert(id) }
            guard depth < 4, let pointer = children?(object) else { return }
            let array = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue()
            for index in 0..<min(32,CFArrayGetCount(array)) {
                if let child = CFArrayGetValueAtIndex(array,index) { visit(child,depth:depth+1) }
            }
        }
        visit(hid,depth:0); return values
    }
    deinit { for handle in handles { dlclose(handle) } }
}

final class DeviceEventCapture {
    var onInput: ((InputPacket) -> Void)?
    var onFailure: ((String) -> Void)?
    /// Enabled explicitly only when the paired receiver understands opaque gesture events.
    var gesturesEnabled = false
    private let lock = NSLock()
    private var active = false
    private var lease = 0.0
    private var loop: CFRunLoop?
    private var worker: Thread?
    private var resolver: PhysicalEventSource?
    private var allowed = Set<UInt64>()
    private var gestureAllowed = Set<UInt64>()
    private var lastPhysicalGestureAt = -Double.infinity
    private var localPointer = CGPoint.zero
    private var counters = ["keyboard":0,"trackpad":0,"excluded":0,"unidentified":0]
    var statistics: [String:Int] {
        lock.lock(); defer { lock.unlock() }
        return counters
    }

    func start(completion: @escaping (Result<Void,Error>) -> Void) {
        stop()
        if let worker, !worker.isFinished { completion(.failure(BridgeError.invalid("Previous input session is still closing"))); return }
        guard HIDCatalog.allowed else { completion(.failure(BridgeError.invalid("Input Monitoring permission required"))); return }
        guard AXIsProcessTrusted() else { completion(.failure(BridgeError.invalid("Accessibility permission required on input source"))); return }
        do { resolver = try PhysicalEventSource() } catch { completion(.failure(error)); return }
        localPointer = CGEvent(source:nil)?.location ?? .zero
        lastPhysicalGestureAt = -Double.infinity
        allowed = Self.senderIdentifiers()
        gestureAllowed = Self.senderIdentifiers(internalTrackpadOnly:true)
        guard !allowed.isEmpty else { completion(.failure(BridgeError.invalid("No identifiable keyboard or internal trackpad"))); return }
        lock.lock(); active = true; lease = ProcessInfo.processInfo.systemUptime
        counters = ["keyboard":0,"trackpad":0,"excluded":0,"unidentified":0]; lock.unlock()
        let thread = Thread { [weak self] in self?.run(completion:completion) }
        thread.name = "KeyBridge device event capture"; thread.qualityOfService = .userInteractive
        worker = thread; thread.start()
    }
    private func run(completion: @escaping (Result<Void,Error>) -> Void) {
        let types: [CGEventType] = [.keyDown,.keyUp,.flagsChanged,.mouseMoved,.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.leftMouseDragged,.rightMouseDragged,.scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap:.cghidEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback: { _,type,event,context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<DeviceEventCapture>.fromOpaque(context).takeUnretainedValue().handle(type,event:event)
        },userInfo:Unmanaged.passUnretained(self).toOpaque()) else {
            lock.lock(); active = false; lock.unlock()
            DispatchQueue.main.async { completion(.failure(BridgeError.invalid("macOS refused the input event tap"))) }; return
        }
        let current = CFRunLoopGetCurrent()!
        lock.lock(); loop = current; let enabled = active; lock.unlock()
        guard enabled else { CFMachPortInvalidate(port); return }
        let source = CFMachPortCreateRunLoopSource(nil,port,0)
        CFRunLoopAddSource(current,source,.commonModes); CGEvent.tapEnable(tap:port,enable:true)
        // Capture interpreted gestures before delivery to apps and Dock. The HID layer
        // precedes gesture recognition, while pointer suppression must happen at HID.
        var gesturePort: CFMachPort?
        var gestureSource: CFRunLoopSource?
        if gesturesEnabled, !gestureAllowed.isEmpty {
            let callback: CGEventTapCallBack = { _,type,event,context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<DeviceEventCapture>.fromOpaque(context).takeUnretainedValue().handle(type,event:event)
            }
            let gestureMask = NativeGestureEvent.eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
            gesturePort = CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:gestureMask,callback:callback,userInfo:Unmanaged.passUnretained(self).toOpaque())
            count(gesturePort == nil ? "gestureTapUnavailable" : "gestureTapSession")
            if let gesturePort {
                gestureSource = CFMachPortCreateRunLoopSource(nil,gesturePort,0)
                CFRunLoopAddSource(current,gestureSource,.commonModes)
                CGEvent.tapEnable(tap:gesturePort,enable:true)
            } else {
                CFMachPortInvalidate(port)
                CFRunLoopRemoveSource(current,source,.commonModes)
                lock.lock(); active = false; loop = nil; lock.unlock()
                DispatchQueue.main.async { completion(.failure(BridgeError.invalid("macOS refused the gesture event tap"))) }
                return
            }
        }
        let watchdog = DispatchSource.makeTimerSource(queue:DispatchQueue(label:"org.keybridge.capture-watchdog",qos:.userInteractive))
        watchdog.schedule(deadline: .now() + .milliseconds(100),repeating:.milliseconds(100))
        watchdog.setEventHandler { [weak self] in
            guard let self else { return }; self.lock.lock()
            let expired = self.active && ProcessInfo.processInfo.systemUptime-self.lease > 1
            self.lock.unlock(); if expired { self.abort("Direct link timed out; local input restored") }
        }
        watchdog.resume()
        defer {
            CGEvent.tapEnable(tap:port,enable:false); CFMachPortInvalidate(port); watchdog.cancel()
            CFRunLoopRemoveSource(current,source,.commonModes)
            if let gesturePort {
                CGEvent.tapEnable(tap:gesturePort,enable:false); CFMachPortInvalidate(gesturePort)
                CFRunLoopRemoveSource(current,gestureSource,.commonModes)
            }
            lock.lock(); active = false; loop = nil; lock.unlock()
        }
        DispatchQueue.main.async { completion(.success(())) }
        CFRunLoopRun()
    }
    func renewLease() { lock.lock(); lease = ProcessInfo.processInfo.systemUptime; lock.unlock() }
    func stop() {
        lock.lock(); active = false; let current = loop; lock.unlock()
        if let current { CFRunLoopStop(current); CFRunLoopWakeUp(current) }
        if let worker, Thread.current !== worker {
            let end = Date().addingTimeInterval(0.4)
            while !worker.isFinished, Date() < end { Thread.sleep(forTimeInterval:0.002) }
        }
    }
    private func rememberLocalPointer(_ type:CGEventType, event:CGEvent) {
        switch type {
        case .mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,
             .leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp:
            localPointer = event.location
        default: break
        }
    }
    private func abort(_ message:String) { stop(); DispatchQueue.main.async { [weak self] in self?.onFailure?(message) } }
    private func count(_ key:String) { lock.lock(); counters[key,default:0] += 1; lock.unlock() }
    private func handle(_ type: CGEventType,event:CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { abort("Input capture stopped by macOS; local input restored"); return Unmanaged.passUnretained(event) }
        lock.lock(); let enabled = active; lock.unlock()
        guard enabled else { return Unmanaged.passUnretained(event) }
        guard event.getIntegerValueField(.eventSourceUserData) != NativeGestureEvent.replayMarker else { return Unmanaged.passUnretained(event) }
        let gesture = NativeGestureEvent.isGesture(event)
        if gesture { count("gestureSeen") }
        if type == .scrollWheel { count("scrollSeen") }
        let senders = resolver?.identifiers(event) ?? []
        // Quartz exposes the originating process, but does not promise that every
        // physical/driver event has PID zero. Preserve identified physical senders.
        // A process-originated pointer event without a physical sender must not
        // become the anchor used to restore the local trackpad position: remote
        // control tools may be moving that pointer from the other Mac.
        let pointerPositionEvent: Bool
        switch type {
        case .mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,
             .leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp:
            pointerPositionEvent = true
        default: pointerPositionEvent = false
        }
        let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
        if pointerPositionEvent, sourcePID > 0 {
            count("processPointer"); count("processPointerPID" + String(sourcePID))
            if senders.isEmpty {
                count("syntheticPointer"); count("syntheticPointerType" + String(type.rawValue))
                count("syntheticPointerPID" + String(sourcePID))
                count("unidentified"); count("unidentifiedType" + String(type.rawValue))
                return Unmanaged.passUnretained(event)
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        let physicalGesture = gesture && !gestureAllowed.isDisjoint(with:senders)
        if physicalGesture { lastPhysicalGestureAt = now }
        // Dock's companion event may omit the HID sender. Accept it only next to an
        // identified internal-trackpad event, never arbitrary synthetic mouse input.
        let companion = gesture && event.type.rawValue == NativeGestureEvent.dockEventType && senders.isEmpty &&
            now-lastPhysicalGestureAt < 0.1 && event.getIntegerValueField(.eventSourceUnixProcessID) == 0
        guard !senders.isEmpty || companion else {
            count("unidentified"); count("unidentifiedType" + String(type.rawValue)); if type == .scrollWheel { count("scrollUnidentified") }
            if gesture { count("gestureUnidentified") }
            rememberLocalPointer(type,event:event)
            return Unmanaged.passUnretained(event)
        }
        let eligible = gesture ? gestureAllowed : allowed
        guard companion || !eligible.isDisjoint(with:senders) else {
            count("excluded"); count("excludedType" + String(type.rawValue));
            for sender in senders.prefix(4) { count("excludedSender" + String(sender)) }
            if type == .scrollWheel { count("scrollExcluded") }
            if gesture { count("gestureExcluded") }
            rememberLocalPointer(type,event:event)
            return Unmanaged.passUnretained(event)
        }
        if companion { count("gestureCompanionMatched") }
        if gesture {
            count("gestureQuartzType" + String(event.type.rawValue))
            count("gestureAppKitType" + String(NSEvent(cgEvent:event)?.type.rawValue ?? 0))
            guard gesturesEnabled, let packet = NativeGestureEvent.encode(event), packet.isValid else {
                count("gestureInvalid"); return Unmanaged.passUnretained(event)
            }
            count("gestureForwarded"); onInput?(packet); return nil
        }
        let packet: InputPacket
        switch type {
        case .keyDown,.keyUp,.flagsChanged:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if code == 53, event.flags.contains([.maskCommand,.maskAlternate,.maskControl]) { abort("Emergency return to local input"); return Unmanaged.passUnretained(event) }
            let down = type == .flagsChanged ? (code == 57 ? event.flags.contains(.maskAlphaShift) : CGEventSource.keyState(.hidSystemState,key:CGKeyCode(code))) : type == .keyDown
            packet = InputPacket(.key,code:code,down:down,flags:event.flags.rawValue,isRepeat:event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            count("keyboard")
        case .mouseMoved,.leftMouseDragged,.rightMouseDragged:
            packet = InputPacket(.move,dx:event.getDoubleValueField(.mouseEventDeltaX),dy:event.getDoubleValueField(.mouseEventDeltaY),flags:event.flags.rawValue); count("trackpad")
            // Dropping a Quartz event does not reliably undo the hardware cursor move.
            // Restore only an identified internal-trackpad move. Other mice pass through
            // unchanged and update the anchor; no global disassociation or delta replay.
            if !gestureAllowed.isDisjoint(with:senders) {
                if CGWarpMouseCursorPosition(localPointer) == .success { count("localTrackpadPointerRestored") }
                else { count("localTrackpadPointerRestoreFailed") }
            }
        case .leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp:
            packet = InputPacket(.button,code:(type == .rightMouseDown || type == .rightMouseUp) ? 1 : 0,down:type == .leftMouseDown || type == .rightMouseDown,flags:event.flags.rawValue); count("trackpad")
        case .scrollWheel:
            packet = InputPacket(.scroll,dx:event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),dy:event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),flags:event.flags.rawValue); count("trackpad")
            count("scrollMatched")
        default: return Unmanaged.passUnretained(event)
        }
        guard packet.isValid else { return Unmanaged.passUnretained(event) }
        onInput?(packet); return nil
    }
    private static func senderIdentifiers(internalTrackpadOnly:Bool = false) -> Set<UInt64> {
        var iterator: io_iterator_t = 0; var identifiers = Set<UInt64>()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOHIDDevice"),&iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        while true {
            let device = IOIteratorNext(iterator); if device == 0 { break }; defer { IOObjectRelease(device) }
            func property(_ name:String) -> Any? { IORegistryEntryCreateCFProperty(device,name as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() }
            let product = property("Product") as? String ?? ""
            let builtIn = (property("Built-In") as? NSNumber)?.boolValue == true
            let page = (property("PrimaryUsagePage") as? NSNumber)?.intValue ?? 0
            let usage = (property("PrimaryUsage") as? NSNumber)?.intValue ?? 0
            let internalDevice = builtIn && product.contains("Internal Keyboard / Trackpad")
            guard internalDevice || (!internalTrackpadOnly && page == 1 && usage == 6 && product.lowercased().contains("keyboard")) else { continue }
            var id:UInt64 = 0; if IORegistryEntryGetRegistryEntryID(device,&id) == KERN_SUCCESS { identifiers.insert(id) }
            var descendants:io_iterator_t = 0
            if IORegistryEntryCreateIterator(device,kIOServicePlane,IOOptionBits(kIORegistryIterateRecursively),&descendants) == KERN_SUCCESS {
                defer { IOObjectRelease(descendants) }
                while true {
                    let child = IOIteratorNext(descendants); if child == 0 { break }
                    if IORegistryEntryGetRegistryEntryID(child,&id) == KERN_SUCCESS { identifiers.insert(id) }
                    IOObjectRelease(child)
                }
            }
        }
        return identifiers
    }
    deinit { stop() }
}
