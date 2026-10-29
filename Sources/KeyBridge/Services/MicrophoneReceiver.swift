import Foundation
import CoreAudio
import KeyBridgeCore

/// Writes small PCM packets through CoreAudio's authenticated custom property IPC.
/// No audio is written to disk. All driver writes share one serial queue.
final class MicrophoneReceiver {
    private let queue = DispatchQueue(label: "org.keybridge.microphone.receiver", qos: .userInteractive)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var session: UInt64 = 0
    private var sequence: UInt64 = 0
    private var pending = 0
    private var generation: String?
    private let lock = NSLock()
    var onFailure: ((String, String) -> Void)?
    static func findDevice() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "org.keybridge.audio.microphone" as CFString
        var result = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), pointer, &size, &result)
        }
        return status == noErr ? result : AudioObjectID(kAudioObjectUnknown)
    }
    static var available: Bool { findDevice() != kAudioObjectUnknown }
    func start(streamID: String, completion: @escaping (String?) -> Void) {
        lock.lock(); generation = streamID; lock.unlock()
        queue.async { [self] in
            guard isCurrent(streamID) else { return }
            end(); device = Self.findDevice()
            guard device != kAudioObjectUnknown else {
                DispatchQueue.main.async { completion("Virtual microphone component is not loaded.") }; return
            }
            session = UInt64.random(in: 1...UInt64.max); sequence = 0
            let status = write(flags: 1, samples: [])
            if status != noErr { end() }
            DispatchQueue.main.async { completion(status == noErr ? nil : "Virtual microphone rejected connection (\(status)).") }
        }
    }
    func push(_ pcm: Data) {
        lock.lock()
        guard let token = generation, pending < 3 else { lock.unlock(); return }
        pending += 1; lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); pending -= 1; lock.unlock() }
            guard isCurrent(token), session != 0, pcm.count == AudioPacket.bytesPerFrame else { return }
            let bytes = [UInt8](pcm)
            let samples = stride(from: 0, to: bytes.count, by: 2).map { index -> Float in
                let value = Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
                return Float(value) / 32768
            }
            sequence += 1
            let status = write(flags: 0, samples: samples)
            if status != noErr {
                end(); DispatchQueue.main.async { [weak self] in self?.onFailure?(token, "Virtual microphone write failed (\(status)).") }
            }
        }
    }
    func stop() {
        lock.lock(); generation = nil; lock.unlock()
        queue.async { [self] in end() }
    }
    private func isCurrent(_ token: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; return generation == token
    }
    private func end() {
        if session != 0 { sequence += 1; _ = write(flags: 2, samples: []) }
        session = 0; sequence = 0; device = AudioObjectID(kAudioObjectUnknown)
    }
    private func write(flags: UInt32, samples: [Float]) -> OSStatus {
        var packet = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian; withUnsafeBytes(of: &little) { packet.append(contentsOf: $0) }
        }
        append(UInt32(0x314d424b)); append(UInt32(1)); append(session); append(sequence)
        append(UInt32(samples.count)); append(flags)
        for sample in samples { append(sample.bitPattern) }
        var data = packet as CFData
        var address = AudioObjectPropertyAddress(mSelector: 0x6b627772,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return withUnsafePointer(to: &data) { pointer in
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<CFData>.size), pointer)
        }
    }
}
