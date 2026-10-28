import Foundation
import CryptoKit
import CoreGraphics
import KeyBridgeCore


private enum CheckState { static var failures = 0 }
private func checkTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { CheckState.failures += 1; print("FAIL \(file):\(line)") }
}
private func checkFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { checkTrue(!value,file:file,line:line) }
private func checkEqual<T:Equatable>(_ a:T,_ b:T,file:StaticString = #filePath,line:UInt = #line) { checkTrue(a == b,file:file,line:line) }
private func checkEqual(_ a:Double,_ b:Double,accuracy:Double,file:StaticString = #filePath,line:UInt = #line) { checkTrue(abs(a-b) <= accuracy,file:file,line:line) }
private func checkGreaterThan(_ a:Int,_ b:Int,file:StaticString = #filePath,line:UInt = #line) { checkTrue(a>b,file:file,line:line) }
private func checkThrows(_ expression:@autoclosure () throws -> Any,file:StaticString = #filePath,line:UInt = #line) {
    do { _ = try expression(); checkTrue(false,file:file,line:line) } catch {}
}

private final class PairHarness {
    let a: SecureSession
    let b: SecureSession
    var queue: [(Bool, Data)] = []
    var codes: [String] = []
    var receivedA: [Message] = []
    var receivedB: [Message] = []
    var failures: [String] = []
    init(pin: @escaping (String) -> String? = { _ in nil }) {
        a = SecureSession(identity: DeviceIdentity(id:"A", name:"A.local", keyboard:true, trackpad:true, canReceive:true), signingKey: .init(), pin:pin)
        b = SecureSession(identity: DeviceIdentity(id:"B", name:"B.local", keyboard:true, trackpad:false, canReceive:true), signingKey: .init(), pin:pin)
        a.sendWire = { [weak self] in self?.queue.append((true,$0)) }
        b.sendWire = { [weak self] in self?.queue.append((false,$0)) }
        a.onPairing = { [weak self] _,code,_ in self?.codes.append(code) }
        b.onPairing = { [weak self] _,code,_ in self?.codes.append(code) }
        a.onFailure = { [weak self] in self?.failures.append($0) }
        b.onFailure = { [weak self] in self?.failures.append($0) }
        a.onMessage = { [weak self] in self?.receivedA.append($0) }
        b.onMessage = { [weak self] in self?.receivedB.append($0) }
    }
    func pump() {
        var budget = 1000
        while !queue.isEmpty, budget > 0 {
            budget -= 1; let (fromA,data) = queue.removeFirst()
            if fromA { b.receive(data) } else { a.receive(data) }
        }
        checkGreaterThan(budget, 0)
    }
    func handshake() { a.start(); b.start(); pump() }
    func paired() { handshake(); a.approve(); b.approve(); pump() }
}

final class KeyBridgeCoreTests {
    private func nativeGesture(subtype: Int64 = 8, value: Double = 0.125) -> CGEvent {
        let event = CGEvent(source:nil)!
        event.type = CGEventType(rawValue:NativeGestureEvent.eventType)!
        event.setIntegerValueField(CGEventField(rawValue:0x6E)!,value:subtype)
        event.setIntegerValueField(CGEventField(rawValue:0x84)!,value:1)
        // Quartz stores magnification and rotation in the same subtype-dependent slot.
        // Build one realistic subtype per event rather than overwriting its value.
        event.setDoubleValueField(CGEventField(rawValue:subtype == 5 ? 0x72 : 0x71)!,value:value)
        return event
    }
    func testNativeGestureRetainsMetadataWithoutActionMapping() {
        let original = nativeGesture()
        let packet = NativeGestureEvent.encode(original)!
        checkEqual(packet.kind,.gesture); checkTrue(packet.isValid)
        let decoded = NativeGestureEvent.decode(packet.nativeEvent!)!
        checkEqual(decoded.type.rawValue,NativeGestureEvent.eventType)
        checkEqual(decoded.getIntegerValueField(CGEventField(rawValue:0x6E)!),8)
        checkEqual(decoded.getIntegerValueField(CGEventField(rawValue:0x84)!),1)
        checkEqual(decoded.getDoubleValueField(CGEventField(rawValue:0x71)!),0.125,accuracy:0.00001)
    }
    func testNativeRotationRetainsItsSubtypeAndValue() {
        let original = nativeGesture(subtype:5,value:-12.5)
        let packet = NativeGestureEvent.encode(original)!
        let decoded = NativeGestureEvent.decode(packet.nativeEvent!)!
        checkTrue(packet.isValid)
        checkEqual(decoded.getIntegerValueField(CGEventField(rawValue:0x6E)!),5)
        checkEqual(decoded.getDoubleValueField(CGEventField(rawValue:0x72)!),-12.5,accuracy:0.00001)
    }
    func testEncryptedNativeGestureSurvivesBluetoothFraming() throws {
        let pair = PairHarness(); pair.paired()
        let route = Route(source:"A",target:"B")
        let packet = NativeGestureEvent.encode(nativeGesture())!
        pair.a.send(Message(.input,route:route,input:packet))
        let wire = pair.queue.removeFirst().1
        checkFalse(String(data:wire,encoding:.utf8)?.contains("nativeEvent") == true)
        let frame = try FrameDecoder.encode(wire); var decoder = FrameDecoder()
        for offset in stride(from:0,to:frame.count,by:7) {
            for received in try decoder.append(Data(frame.dropFirst(offset).prefix(7))) { pair.b.receive(received) }
        }
        checkEqual(pair.receivedB.last?.input,packet)
        checkEqual(pair.receivedB.last?.route?.token,route.token)
        checkTrue(pair.failures.isEmpty)
    }
    func testNativeGestureRejectsOtherQuartzEventsAndUnboundedData() {
        let key = CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true)!
        checkTrue(NativeGestureEvent.encode(key) == nil)
        checkTrue(NativeGestureEvent.decode(key.data! as Data) == nil)
        checkFalse(InputPacket(.gesture,code:29,nativeEvent:key.data! as Data).isValid)
        checkFalse(InputPacket(.gesture,code:29,nativeEvent:Data()).isValid)
        checkFalse(InputPacket(.gesture,code:29,nativeEvent:Data([1,2,3])).isValid)
        checkFalse(InputPacket(.gesture,code:29,nativeEvent:Data(repeating:0,count:NativeGestureEvent.maximumBytes+1)).isValid)
        checkFalse(InputPacket(.key,code:0,nativeEvent:NativeGestureEvent.encode(nativeGesture())!.nativeEvent).isValid)
        let pair = PairHarness(); pair.paired()
        pair.a.send(Message(.input,route:Route(source:"A",target:"B"),input:InputPacket(.gesture,code:29,nativeEvent:key.data! as Data)))
        checkFalse(pair.a.ready); checkTrue(pair.receivedB.isEmpty); checkEqual(pair.failures.count,1)
    }
    func testNativeGestureReplayMarkerAndCancellation() {
        let original = nativeGesture()
        let event = NativeGestureEvent.decode(NativeGestureEvent.encode(original)!.nativeEvent!)!
        NativeGestureEvent.prepareForReplay(event,source:CGEventSource(stateID:.privateState),at:CGPoint(x:51,y:73),timestamp:123456)
        checkEqual(event.location,CGPoint(x:51,y:73)); checkEqual(event.timestamp,123456)
        checkTrue(NativeGestureEvent.encode(event) == nil)
        checkFalse(NativeGestureEvent.isComplete(event))
        let cancelled = NativeGestureEvent.cancelledCopy(of:event)!
        checkTrue(NativeGestureEvent.isComplete(cancelled))
        checkFalse(NativeGestureEvent.isComplete(original))
        checkEqual(cancelled.type.rawValue,29)
        checkEqual(cancelled.getDoubleValueField(CGEventField(rawValue:0x71)!),0.125,accuracy:0.00001)
    }
    func testLegacyPeerDoesNotAdvertiseNativeGestureSupport() throws {
        let json = Data(#"{"id":"old","name":"old.local","keyboard":true,"trackpad":true,"canReceive":true}"#.utf8)
        let old = try JSONDecoder().decode(DeviceIdentity.self,from:json)
        checkTrue(old.nativeGestureVersion == nil)
        let pair = PairHarness(); pair.paired()
        checkEqual(pair.a.peer?.nativeGestureVersion,NativeGestureEvent.version)
    }
    func testBothDevicesDisplaySamePairingCode() {
        let pair = PairHarness(); pair.handshake()
        checkEqual(pair.codes.count, 2); checkEqual(pair.codes.first, pair.codes.last)
        checkEqual(pair.codes.first?.count, 6); checkFalse(pair.a.ready); checkFalse(pair.b.ready)
    }
    func testOneApprovalDoesNotEnableInput() {
        let pair = PairHarness(); pair.handshake(); pair.a.approve(); pair.pump()
        checkFalse(pair.a.ready); checkFalse(pair.b.ready)
        pair.a.send(Message(.input, input: InputPacket(.key, code:0, down:true)))
        checkTrue(pair.queue.isEmpty); checkTrue(pair.receivedB.isEmpty)
    }
    func testApprovedEncryptedMessagesReachOnlyOtherDevice() {
        let pair = PairHarness(); pair.paired()
        checkTrue(pair.a.ready); checkTrue(pair.b.ready)
        pair.a.send(Message(.input, route: Route(source:"A",target:"B"), input:InputPacket(.key,code:0,down:true)))
        checkTrue(pair.queue[0].1.count < 96)
        checkFalse(String(data:pair.queue[0].1,encoding:.utf8)?.contains("key") == true)
        pair.pump(); checkEqual(pair.receivedB.last?.input?.code, 0)
        checkTrue(pair.failures.isEmpty)
    }
    func testReplayIsRejectedBeforeSecondEvent() {
        let pair = PairHarness(); pair.paired(); pair.a.send(Message(.ping, stamp:1))
        let wire = pair.queue.removeFirst().1
        pair.b.receive(wire); pair.b.receive(wire)
        checkEqual(pair.receivedB.count, 1); checkEqual(pair.failures.count, 1)
        checkFalse(pair.b.ready)
    }
    func testCiphertextTamperingClosesSession() {
        let pair = PairHarness(); pair.paired(); pair.a.send(Message(.ping, stamp:1))
        var wire = pair.queue.removeFirst().1; wire[wire.count - 5] ^= 1
        pair.b.receive(wire); checkFalse(pair.b.ready); checkEqual(pair.failures.count, 1)
    }
    func testDirectionalKeysRejectReflection() {
        let pair = PairHarness(); pair.paired(); pair.a.send(Message(.ping, stamp:1))
        pair.a.receive(pair.queue.removeFirst().1)
        checkFalse(pair.a.ready); checkTrue(pair.receivedA.isEmpty)
    }
    func testFramingSurvivesSingleByteBluetoothFragments() throws {
        let payload = Data((0..<2000).map { UInt8($0 % 256) })
        let frame = try FrameDecoder.encode(payload); var decoder = FrameDecoder(); var output:[Data] = []
        for byte in frame { output += try decoder.append(Data([byte])) }
        checkEqual(output,[payload])
    }
    func testFramingRejectsUnboundedOrEmptyMessages() {
        var decoder = FrameDecoder()
        checkThrows(try decoder.append(Data([255,255,255,255])))
        checkThrows(try FrameDecoder.encode(Data()))
        checkThrows(try FrameDecoder.encode(Data(repeating:0,count:FrameDecoder.maximum + 1)))
    }
    func testKeyboardPreservesModifierAndReleaseOrder() throws {
        var decoder = KeyboardReportDecoder()
        let down = try decoder.decode([1,2,0,4,0,0,0,0,0],reportID:1)
        checkTrue(down.contains { $0.code == 0 && $0.down && $0.flags == 1 << 17 })
        let release = try decoder.decode([1,0,0,0,0,0,0,0,0],reportID:1)
        checkEqual(Set(release.map(\.code)), [0,56]); checkTrue(release.allSatisfy { !$0.down && $0.flags == 0 })
    }
    func testKeyboardRolloverDoesNotReleaseHeldKey() throws {
        var decoder = KeyboardReportDecoder()
        _ = try decoder.decode([1,0,0,4,0,0,0,0,0],reportID:1)
        checkTrue(try decoder.decode([1,0,0,1,1,1,1,1,1],reportID:1).isEmpty)
        checkTrue(decoder.pressed.contains(4))
        checkEqual(try decoder.decode([1,0,0,0,0,0,0,0,0],reportID:1).first?.down, false)
    }
    func testAppleSPITrackpadDecodesContactCoordinates() throws {
        var bytes = [UInt8](repeating:0,count:76); bytes[0]=2; bytes[30]=1
        bytes[50]=0xE8; bytes[51]=3; bytes[52]=0xD0; bytes[53]=7; bytes[64]=1
        let frame = try AppleTrackpadReport.decode(bytes)
        checkEqual(frame.contacts,[TrackpadContact(x:1000,y:-2000)])
        bytes[30]=16; checkThrows(try AppleTrackpadReport.decode(bytes))
        checkThrows(try AppleTrackpadReport.decode([2,1,1,1]))
    }
    func testTrackpadOneFingerMovesTwoFingerScrolls() {
        var decoder = TrackpadInterpreter()
        _ = decoder.consume(TrackpadFrame(contacts:[.init(x:100,y:100)],pressed:false), time:0)
        let movement = decoder.consume(TrackpadFrame(contacts:[.init(x:110,y:120)],pressed:false),time:0.01)
        checkEqual(movement.first?.kind,.move); checkEqual(movement.first?.dx ?? 0,1.2,accuracy:0.001)
        _ = decoder.consume(TrackpadFrame(contacts:[.init(x:110,y:120),.init(x:210,y:220)],pressed:false),time:0.02)
        let scroll = decoder.consume(TrackpadFrame(contacts:[.init(x:120,y:130),.init(x:220,y:230)],pressed:false),time:0.03)
        checkEqual(scroll.first?.kind,.scroll)
    }
    func testTrackpadTapProducesBalancedClick() {
        var decoder = TrackpadInterpreter()
        _ = decoder.consume(TrackpadFrame(contacts:[.init(x:100,y:100)],pressed:false),time:0)
        let click = decoder.consume(TrackpadFrame(contacts:[],pressed:false),time:0.1)
        checkEqual(click.map(\.down),[true,false]); checkTrue(click.allSatisfy { $0.kind == .button })
    }
    func testInvalidInputCannotReachQuartz() {
        checkFalse(InputPacket(.move,dx:.nan).isValid)
        checkFalse(InputPacket(.move,dy:100_000).isValid)
        checkFalse(InputPacket(.key,code:999).isValid)
        checkFalse(InputPacket(.button,code:7).isValid)
    }
}

@main
struct KeyBridgeCheckRunner {
    static func main() {
        let tests = KeyBridgeCoreTests()
        run("testBothDevicesDisplaySamePairingCode") { tests.testBothDevicesDisplaySamePairingCode() }
        run("testOneApprovalDoesNotEnableInput") { tests.testOneApprovalDoesNotEnableInput() }
        run("testApprovedEncryptedMessagesReachOnlyOtherDevice") { tests.testApprovedEncryptedMessagesReachOnlyOtherDevice() }
        run("testReplayIsRejectedBeforeSecondEvent") { tests.testReplayIsRejectedBeforeSecondEvent() }
        run("testCiphertextTamperingClosesSession") { tests.testCiphertextTamperingClosesSession() }
        run("testDirectionalKeysRejectReflection") { tests.testDirectionalKeysRejectReflection() }
        run("testFramingSurvivesSingleByteBluetoothFragments") { try tests.testFramingSurvivesSingleByteBluetoothFragments() }
        run("testFramingRejectsUnboundedOrEmptyMessages") { tests.testFramingRejectsUnboundedOrEmptyMessages() }
        run("testKeyboardPreservesModifierAndReleaseOrder") { try tests.testKeyboardPreservesModifierAndReleaseOrder() }
        run("testKeyboardRolloverDoesNotReleaseHeldKey") { try tests.testKeyboardRolloverDoesNotReleaseHeldKey() }
        run("testAppleSPITrackpadDecodesContactCoordinates") { try tests.testAppleSPITrackpadDecodesContactCoordinates() }
        run("testTrackpadOneFingerMovesTwoFingerScrolls") { tests.testTrackpadOneFingerMovesTwoFingerScrolls() }
        run("testTrackpadTapProducesBalancedClick") { tests.testTrackpadTapProducesBalancedClick() }
        run("testInvalidInputCannotReachQuartz") { tests.testInvalidInputCannotReachQuartz() }
        run("testNativeGestureRetainsMetadataWithoutActionMapping") { tests.testNativeGestureRetainsMetadataWithoutActionMapping() }
        run("testNativeRotationRetainsItsSubtypeAndValue") { tests.testNativeRotationRetainsItsSubtypeAndValue() }
        run("testEncryptedNativeGestureSurvivesBluetoothFraming") { try tests.testEncryptedNativeGestureSurvivesBluetoothFraming() }
        run("testNativeGestureRejectsOtherQuartzEventsAndUnboundedData") { tests.testNativeGestureRejectsOtherQuartzEventsAndUnboundedData() }
        run("testNativeGestureReplayMarkerAndCancellation") { tests.testNativeGestureReplayMarkerAndCancellation() }
        run("testLegacyPeerDoesNotAdvertiseNativeGestureSupport") { try tests.testLegacyPeerDoesNotAdvertiseNativeGestureSupport() }
        CheckState.failures += runWiredDiagnosticChecks()
        print("Checks complete: \(CheckState.failures) failures")
        exit(CheckState.failures == 0 ? 0 : 1)
    }
    static func run(_ name:String,_ body:() throws -> Void) {
        let before = CheckState.failures
        do { try body() } catch { CheckState.failures += 1; print("FAIL \(name): \(error)") }
        if before == CheckState.failures { print("PASS \(name)") }
    }
}
