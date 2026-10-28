import Foundation
import CryptoKit
import SystemConfiguration
import KeyBridgeCore
import Darwin

final class IdentityVault {
    let signingKey: Curve25519.Signing.PrivateKey
    let id: String
    init() throws {
        let directory = Diagnostics.directory
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
        let file = directory.appendingPathComponent("device-identity.key")
        if FileManager.default.fileExists(atPath:file.path) {
            let descriptor = Darwin.open(file.path,O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw BridgeError.invalid("Cannot open device identity") }
            defer { Darwin.close(descriptor) }
            var attributes = stat()
            guard fstat(descriptor,&attributes) == 0, attributes.st_uid == getuid(), attributes.st_mode & 0o077 == 0, attributes.st_size == 32 else {
                throw BridgeError.invalid("Device identity permissions or length invalid")
            }
            var bytes = [UInt8](repeating:0,count:32)
            guard Darwin.read(descriptor,&bytes,32) == 32 else { throw BridgeError.invalid("Cannot read device identity") }
            signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation:Data(bytes))
        } else {
            let key = Curve25519.Signing.PrivateKey()
            // The parent is owner-only before the atomic write, including its temporary file.
            try key.rawRepresentation.write(to:file,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
            signingKey = key
        }
        id = SHA256.hash(data: signingKey.publicKey.rawRepresentation).map { String(format: "%02x", $0) }.joined()
    }
    static var networkName: String {
        if let name = SCDynamicStoreCopyLocalHostName(nil) as String?, !name.isEmpty { return name + ".local" }
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }
    func pinned(_ peerID: String) -> String? { UserDefaults.standard.string(forKey: "peer." + peerID) }
    func trust(_ peerID: String, fingerprint: String) { UserDefaults.standard.set(fingerprint, forKey: "peer." + peerID) }
    func forgetPeers() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("peer.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
