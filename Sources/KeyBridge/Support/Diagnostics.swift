import Foundation
import AppKit
import KeyBridgeCore

enum Diagnostics {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KeyBridge", isDirectory: true)
    }
    static var statusFile: URL { directory.appendingPathComponent("status.json") }
    static func write(store: BridgeStore) {
        let dictionary: [String:Any] = [
            "version":"0.2.0", "updatedAt":ISO8601DateFormatter().string(from:Date()),
            "networkName":store.local.name, "mode":store.mode.rawValue,
            "state":String(describing:store.phase), "authenticated":store.ready,
            "forwarding":store.forwarding, "inputMonitoring":store.inputPermission,
            "accessibility":store.receivePermission,
            "nativeGesturesEnabled":store.gestureForwardingEnabled,
            "peerNativeGestureVersion":store.peer?.nativeGestureVersion ?? 0,
            "hasKeyboard":store.local.keyboard, "hasSupportedTrackpad":store.local.trackpad,
            "source":store.options.first(where: { $0.id == store.sourceID })?.name ?? "",
            "target":store.options.first(where: { $0.id == store.targetID })?.name ?? "",
            "peer":store.peer?.name ?? "", "roundTripMS":store.latency ?? -1,
            "detail":store.detail, "error":store.error
            ,"identityLoading":store.identityLoading,"identityNeedsAuthorization":store.identityNeedsAuthorization,
            "discoveredDevices":store.discoveries.map(\.name)
            ,"inputCounters":store.inputStatistics, "wired":store.wiredDiagnostics
        ]
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let data = try JSONSerialization.data(withJSONObject:dictionary,options:[.sortedKeys,.prettyPrinted])
            try data.write(to:statusFile,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:statusFile.path)
        } catch { /* Diagnostic writes must never interrupt input recovery. */ }
    }
    static func printHardware() {
        let devices = HIDCatalog.scan()
        let snapshot: [String:Any] = ["networkName":IdentityVault.networkName,
            "supportedInputs":devices.map { ["product":$0.product,"kind":$0.kind == .keyboard ? "keyboard" : "trackpad"] },
            "thunderboltInterfaces":Array(WiredTransport.thunderboltBridges()),
            "wiredDiagnosis":WiredSystemSnapshot.read().diagnosis.stage.rawValue,
            "note":"Read-only hardware inventory; no HID devices opened and no input injected."]
        if let data = try? JSONSerialization.data(withJSONObject:snapshot,options:[.prettyPrinted,.sortedKeys]), let string = String(data:data,encoding:.utf8) { print(string) }
    }
}
