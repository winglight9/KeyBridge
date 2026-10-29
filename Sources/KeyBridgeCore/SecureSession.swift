import Foundation
import CryptoKit

private struct HelloBody: Codable {
    var version: Int
    var identity: DeviceIdentity
    var ephemeral: Data
    var signing: Data
    var nonce: Data
}
private struct Hello: Codable { var body: HelloBody; var signature: Data }
private struct SequencedMessage: Codable { var sequence: UInt64; var message: Message }

/// Calls must be serialized. No input is accepted until both users approved the identity.
public final class SecureSession {
    public var sendWire: ((Data) -> Void)?
    public var onPairing: ((DeviceIdentity, String, Bool) -> Void)?
    public var onReady: ((DeviceIdentity, String) -> Void)?
    public var onMessage: ((Message) -> Void)?
    public var onFailure: ((String) -> Void)?
    public private(set) var ready = false
    public private(set) var peer: DeviceIdentity?
    public private(set) var fingerprint: String?
    private let identity: DeviceIdentity
    private let signingKey: Curve25519.Signing.PrivateKey
    private let ephemeral = Curve25519.KeyAgreement.PrivateKey()
    private let nonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }()
    private let decoder = JSONDecoder()
    private let pin: (String) -> String?
    private var key: SymmetricKey?
    private var outboundKey: SymmetricKey?
    private var inboundKey: SymmetricKey?
    private var localApproved = false
    private var remoteApproved = false
    private var sent: UInt64 = 0
    private var received: UInt64 = 0
    private var failed = false
    private var incomingAudio: (id: String, sequence: UInt64)?
    private var outgoingAudio: (id: String, sequence: UInt64)?
    public init(identity: DeviceIdentity, signingKey: Curve25519.Signing.PrivateKey, pin: @escaping (String) -> String?) {
        self.identity = identity; self.signingKey = signingKey; self.pin = pin
    }
    public func start() {
        do {
            // Legacy peers verify by decoding and re-encoding the signed Hello.
            // Announce new optional capabilities only after that legacy handshake;
            // adding an unknown field here would invalidate their signature check.
            var handshakeIdentity = identity
            handshakeIdentity.microphoneVersion = nil
            let body = HelloBody(version: 1, identity: handshakeIdentity, ephemeral: ephemeral.publicKey.rawRepresentation,
                                 signing: signingKey.publicKey.rawRepresentation, nonce: nonce)
            let signature = try signingKey.signature(for: encoder.encode(body))
            sendWire?(Data([1]) + (try encoder.encode(Hello(body: body, signature: signature))))
        } catch { fail(error.localizedDescription) }
    }
    public func receive(_ data: Data) {
        guard !failed else { return }
        do {
            guard data.count <= FrameDecoder.maximum else { throw BridgeError.invalid("Packet too large") }
            if data.first == 1 { try accept(decoder.decode(Hello.self, from:Data(data.dropFirst()))); return }
            guard data.first == 2, let key = inboundKey else { throw BridgeError.invalid("Handshake required") }
            let sealed = Data(data.dropFirst())
            let plaintext = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: sealed), using: key, authenticating: Data("KeyBridge/v1".utf8))
            let packet: SequencedMessage
            if let (sequence,message) = try CompactInput.decode(plaintext) { packet = SequencedMessage(sequence:sequence,message:message) }
            else { packet = try decoder.decode(SequencedMessage.self, from: plaintext) }
            guard packet.sequence == received + 1 else { throw BridgeError.invalid("Replay or missing packet") }
            received = packet.sequence
            if packet.message.kind == .approved { remoteApproved = true; completeIfReady(); return }
            guard ready else { throw BridgeError.invalid("Pairing approval required") }
            if let input = packet.message.input, !input.isValid { throw BridgeError.invalid("Invalid input event") }
            if packet.message.kind == .identity, let announced = packet.message.identity,
               announced.id == peer?.id { peer = announced }
            try validateAudio(packet.message, inbound: true)
            onMessage?(packet.message)
        } catch { fail(error.localizedDescription) }
    }
    private func accept(_ hello: Hello) throws {
        guard key == nil, hello.body.version == 1, hello.body.identity.id != identity.id,
              hello.body.identity.name.utf8.count <= 255, hello.body.nonce.count == 32 else {
            throw BridgeError.invalid("Invalid or duplicate handshake")
        }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: hello.body.signing)
        guard publicKey.isValidSignature(hello.signature, for: try encoder.encode(hello.body)) else { throw BridgeError.invalid("Identity signature invalid") }
        let remoteKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: hello.body.ephemeral)
        let secret = try ephemeral.sharedSecretFromKeyAgreement(with: remoteKey)
        let ordered = [ephemeral.publicKey.rawRepresentation + nonce, hello.body.ephemeral + hello.body.nonce].sorted { $0.lexicographicallyPrecedes($1) }
        let salt = Data(SHA256.hash(data: ordered[0] + ordered[1]))
        key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("KeyBridge session v1".utf8), outputByteCount: 32)
        outboundKey = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("KeyBridge from \(identity.id)".utf8), outputByteCount: 32)
        inboundKey = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("KeyBridge from \(hello.body.identity.id)".utf8), outputByteCount: 32)
        peer = hello.body.identity
        let fp = SHA256.hash(data: hello.body.signing).map { String(format: "%02x", $0) }.joined()
        fingerprint = fp
        let existing = pin(hello.body.identity.id)
        if existing == fp { approve() }
        else {
            let digits = key!.withUnsafeBytes { Data(SHA256.hash(data: Data($0) + Data("compare code".utf8))) }
            let number = digits.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
            onPairing?(hello.body.identity, String(format: "%06u", number), existing != nil)
        }
    }
    public func approve() {
        guard key != nil, !failed else { return }
        localApproved = true; sendEncrypted(Message(.approved)); completeIfReady()
    }
    private func completeIfReady() {
        guard !ready, !failed, localApproved, remoteApproved, let peer, let fingerprint else { return }
        ready = true; onReady?(peer, fingerprint)
    }
    public func send(_ message: Message) {
        guard ready, !failed else { return }
        // Unknown enum cases cannot be decoded by older peers. Never send audio to them.
        if message.kind.isAudio {
            guard identity.microphoneVersion == AudioPacket.version,
                  peer?.microphoneVersion == AudioPacket.version else { return }
        }
        do { try validateAudio(message, inbound: false) }
        catch { return } // A stopped producer can still have a queued frame; leave input sharing alive.
        sendEncrypted(message)
    }
    private func validateAudio(_ message: Message, inbound: Bool) throws {
        guard message.kind.isAudio else {
            guard message.audio == nil else { throw BridgeError.invalid("Audio payload on a non-audio message") }
            return
        }
        guard identity.microphoneVersion == AudioPacket.version,
              peer?.microphoneVersion == AudioPacket.version,
              message.input == nil, let audio = message.audio else {
            throw BridgeError.invalid("Unsupported or missing microphone payload")
        }
        if message.kind == .audioFrame {
            let stream = inbound ? incomingAudio : outgoingAudio
            guard audio.isValidFrame, let stream, stream.id == audio.streamID,
                  audio.sequence > stream.sequence else {
                throw BridgeError.invalid("Invalid microphone format, size, stream or sequence")
            }
            // Gaps are allowed: bounded capture queues intentionally discard old frames.
            if inbound { incomingAudio = (audio.streamID, audio.sequence) }
            else { outgoingAudio = (audio.streamID, audio.sequence) }
            return
        }
        guard audio.isValidControl else { throw BridgeError.invalid("Invalid microphone control payload") }
        switch message.kind {
        case .audioStart:
            // A repeated start must not reset the sequence window for this stream.
            if inbound {
                if incomingAudio?.id != audio.streamID { incomingAudio = (audio.streamID, 0) }
            } else if outgoingAudio?.id != audio.streamID { outgoingAudio = (audio.streamID, 0) }
        case .audioStop, .audioError:
            if inbound {
                if incomingAudio?.id == audio.streamID { incomingAudio = nil }
                if outgoingAudio?.id == audio.streamID { outgoingAudio = nil }
            } else if outgoingAudio?.id == audio.streamID { outgoingAudio = nil }
            // Keep accepting already-in-flight incoming frames after our stop request;
            // the caller discards them until the peer's ordered stop arrives.
        default: break
        }
    }
    private func sendEncrypted(_ message: Message) {
        do {
            guard let key = outboundKey else { throw BridgeError.invalid("No session key") }
            sent += 1
            let plaintext = try CompactInput.encode(sequence:sent,message:message) ?? encoder.encode(SequencedMessage(sequence: sent, message: message))
            let sealed = try ChaChaPoly.seal(plaintext, using: key, authenticating: Data("KeyBridge/v1".utf8)).combined
            sendWire?(Data([2]) + sealed)
        } catch { fail(error.localizedDescription) }
    }
    private func fail(_ text: String) { guard !failed else { return }; failed = true; ready = false; key = nil; outboundKey = nil; inboundKey = nil; onFailure?(text) }
}
