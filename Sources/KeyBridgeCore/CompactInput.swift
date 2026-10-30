import Foundation

/// Forty bytes before encryption, so high-rate trackpad motion fits a small BLE notification.
enum CompactInput {
    static func encode(sequence: UInt64, message: Message) throws -> Data? {
        guard message.kind == .input else { return nil }
        // Gesture events retain their complete Quartz payload and use the encrypted JSON envelope.
        // Ordinary key/motion packets keep the existing forty-byte representation.
        if message.input?.kind == .gesture || message.input?.kind == .nativeKey {
            guard message.input?.isValid == true, let token = message.route?.token, UUID(uuidString:token) != nil else {
                throw BridgeError.invalid("Invalid native input route")
            }
            return nil
        }
        guard let input = message.input, input.isValid, let token = message.route?.token, let id = UUID(uuidString: token) else {
            throw BridgeError.invalid("Input route missing")
        }
        var data = Data([0x49])
        append(sequence, to:&data)
        var uuid = id.uuid; withUnsafeBytes(of:&uuid) { data.append(contentsOf:$0) }
        data.append([InputPacket.Kind.key,.move,.button,.scroll].firstIndex(of: input.kind).map(UInt8.init)!)
        data.append(UInt8(input.code)); data.append((input.down ? 1 : 0) | (input.isRepeat ? 2 : 0))
        append(UInt32(truncatingIfNeeded:input.flags),to:&data)
        append(Float(input.dx).bitPattern,to:&data); append(Float(input.dy).bitPattern,to:&data)
        return data
    }
    static func decode(_ data: Data) throws -> (UInt64, Message)? {
        guard data.first == 0x49 else { return nil }
        guard data.count == 40 else { throw BridgeError.invalid("Invalid compact input length") }
        let bytes = Array(data)
        func number(_ start: Int, _ length:Int) -> UInt64 { bytes[start..<(start+length)].reduce(0) { ($0 << 8) | UInt64($1) } }
        var uuid = UUID().uuid
        withUnsafeMutableBytes(of:&uuid) { $0.copyBytes(from:bytes[9..<25]) }
        guard bytes[25] < 4, bytes[27] & 0xFC == 0 else { throw BridgeError.invalid("Invalid compact input") }
        let kind = [InputPacket.Kind.key,.move,.button,.scroll][Int(bytes[25])]
        let packet = InputPacket(kind, code:Int(bytes[26]), down:bytes[27] & 1 != 0,
            dx:Double(Float(bitPattern:UInt32(number(32,4)))),dy:Double(Float(bitPattern:UInt32(number(36,4)))),
            flags:number(28,4), isRepeat:bytes[27] & 2 != 0)
        guard packet.isValid else { throw BridgeError.invalid("Invalid input event") }
        return (number(1,8),Message(.input,route:Route(source:"",target:"",token:UUID(uuid:uuid).uuidString),input:packet))
    }
    private static func append<T:FixedWidthInteger>(_ value:T,to data:inout Data) {
        var network = value.bigEndian; withUnsafeBytes(of:&network) { data.append(contentsOf:$0) }
    }
}
