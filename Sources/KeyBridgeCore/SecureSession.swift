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
    public init(identity: DeviceIdentity, signingKey: Curve25519.Signing.PrivateKey, pin: @escaping (String) -> String?) {
        self.identity = identity; self.signingKey = signingKey; self.pin = pin
    }
    public func start() {
        do {
            let body = HelloBody(version: 1, identity: identity, ephemeral: ephemeral.publicKey.rawRepresentation,
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
        sendEncrypted(message)
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
