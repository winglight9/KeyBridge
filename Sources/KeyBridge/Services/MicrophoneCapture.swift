import Foundation
import AVFoundation
import CoreAudio
import KeyBridgeCore

/// Opt-in live capture only. Call control methods on the main thread; callbacks
/// are delivered on the main thread. Audio is never written to disk.
final class MicrophoneCapture {
    static var permissionStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }
    /// Invoke only in response to the user's explicit microphone sharing action.
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }
    private final class Conversion {
        let streamID: String
        let converter: AVAudioConverter
        let outputFormat: AVAudioFormat
        var accumulated = Data()
        var sequence: UInt64 = 0
        init(streamID: String, converter: AVAudioConverter, outputFormat: AVAudioFormat) {
            self.streamID = streamID; self.converter = converter; self.outputFormat = outputFormat
        }
    }
    private let lock = NSLock()
    private let conversionQueue = DispatchQueue(label: "org.keybridge.microphone.convert", qos: .userInitiated)
    private let maximumQueuedBuffers = 4
    private let maximumQueuedFrames = 4
    private var generation = UUID()
    private var active = false
    private var pendingInput: [AVAudioPCMBuffer] = []
    private var pendingOutput: [AudioPacket] = []
    private var inputScheduled = false
    private var outputScheduled = false
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var configurationObserver: NSObjectProtocol?
    private var onFrame: ((AudioPacket) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var counts: [String:Int] = [:]
    private(set) var isRunning = false
    var statistics: [String:Int] { lock.lock(); defer { lock.unlock() }; return counts }

    func start(streamID: String, onFrame: @escaping (AudioPacket) -> Void,
               onFailure: @escaping (String) -> Void,
               completion: @escaping (Result<Void,Error>) -> Void) {
        precondition(Thread.isMainThread)
        stop()
        guard UUID(uuidString: streamID) != nil else {
            completion(.failure(BridgeError.invalid("Invalid microphone stream identifier"))); return
        }
        guard Self.permissionStatus == "authorized" else {
            completion(.failure(BridgeError.invalid("Microphone permission required"))); return
        }
        do {
            try Self.rejectVirtualDefaultInput()
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate >= 8_000, inputFormat.sampleRate <= 192_000,
                  inputFormat.channelCount > 0, inputFormat.channelCount <= 32,
                  let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                    sampleRate: Double(AudioPacket.sampleRate), channels: 1, interleaved: true),
                  let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw BridgeError.invalid("Unsupported microphone input format")
            }
            converter.primeMethod = .none
            converter.downmix = true
            let conversion = Conversion(streamID: streamID, converter: converter, outputFormat: outputFormat)
            let token = UUID()
            lock.lock(); generation = token; active = true; counts = [:]; lock.unlock()
            self.onFrame = onFrame; self.onFailure = onFailure; self.engine = engine
            input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(AudioPacket.samplesPerFrame), format: inputFormat) { [weak self] buffer, _ in
                self?.enqueue(buffer, token: token, conversion: conversion)
            }
            tapInstalled = true
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                object: engine, queue: .main) { [weak self] _ in
                    self?.fail("Microphone device changed. Start sharing again.", token: token)
                }
            engine.prepare(); try engine.start(); isRunning = true
            completion(.success(()))
        } catch {
            stop(); completion(.failure(error))
        }
    }
    func stop() {
        precondition(Thread.isMainThread)
        lock.lock(); active = false; generation = UUID()
        pendingInput.removeAll(); pendingOutput.removeAll()
        inputScheduled = false; outputScheduled = false; lock.unlock()
        if let observer = configurationObserver { NotificationCenter.default.removeObserver(observer) }
        configurationObserver = nil
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0) }
        tapInstalled = false; engine?.stop(); engine = nil; isRunning = false
        onFrame = nil; onFailure = nil
    }
    private func enqueue(_ original: AVAudioPCMBuffer, token: UUID, conversion: Conversion) {
        guard original.frameLength > 0, original.frameLength <= 8_192 else { return }
        lock.lock(); let valid = active && generation == token; lock.unlock()
        guard valid, let copy = AVAudioPCMBuffer(pcmFormat: original.format, frameCapacity: original.frameLength) else { return }
        copy.frameLength = original.frameLength
        let from = UnsafeMutableAudioBufferListPointer(original.mutableAudioBufferList)
        let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard from.count == to.count else { return }
        for index in 0..<from.count {
            guard let source = from[index].mData, let destination = to[index].mData,
                  from[index].mDataByteSize <= to[index].mDataByteSize else { return }
            memcpy(destination, source, Int(from[index].mDataByteSize))
        }
        lock.lock()
        guard active, generation == token else { lock.unlock(); return }
        if pendingInput.count >= maximumQueuedBuffers {
            pendingInput.removeFirst(); counts["droppedInputBuffers", default: 0] += 1
        }
        pendingInput.append(copy)
        let schedule = !inputScheduled; inputScheduled = true; lock.unlock()
        if schedule { conversionQueue.async { [weak self] in self?.drainInput(token: token, conversion: conversion) } }
    }
    private func drainInput(token: UUID, conversion: Conversion) {
        while true {
            lock.lock()
            guard active, generation == token else { lock.unlock(); return }
            guard !pendingInput.isEmpty else { inputScheduled = false; lock.unlock(); return }
            let input = pendingInput.removeFirst(); lock.unlock()
            let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * conversion.outputFormat.sampleRate / input.format.sampleRate) + 64)
            guard let output = AVAudioPCMBuffer(pcmFormat: conversion.outputFormat, frameCapacity: capacity) else {
                fail("Cannot allocate microphone conversion buffer", token: token); return
            }
            var supplied = false
            var error: NSError?
            let status = conversion.converter.convert(to: output, error: &error) { _, inputStatus in
                if supplied { inputStatus.pointee = .noDataNow; return nil }
                supplied = true; inputStatus.pointee = .haveData; return input
            }
            guard status != .error, error == nil else {
                fail(error?.localizedDescription ?? "Microphone conversion failed", token: token); return
            }
            guard output.frameLength > 0, let channel = output.int16ChannelData?[0] else { continue }
            // Apple Silicon and supported Intel Macs both use little-endian PCM.
            conversion.accumulated.append(Data(bytes: channel, count: Int(output.frameLength) * MemoryLayout<Int16>.size))
            while conversion.accumulated.count >= AudioPacket.bytesPerFrame {
                let pcm = Data(conversion.accumulated.prefix(AudioPacket.bytesPerFrame))
                conversion.accumulated.removeFirst(AudioPacket.bytesPerFrame)
                guard conversion.sequence < UInt64.max else { fail("Microphone sequence exhausted", token: token); return }
                conversion.sequence += 1
                enqueueOutput(AudioPacket(streamID: conversion.streamID, sequence: conversion.sequence, pcm: pcm), token: token)
            }
        }
    }
    private func enqueueOutput(_ packet: AudioPacket, token: UUID) {
        lock.lock()
        guard active, generation == token else { lock.unlock(); return }
        counts["capturedFrames", default: 0] += 1
        if pendingOutput.count >= maximumQueuedFrames {
            pendingOutput.removeFirst(); counts["droppedFrames", default: 0] += 1
        }
        pendingOutput.append(packet)
        let schedule = !outputScheduled; outputScheduled = true; lock.unlock()
        if schedule { DispatchQueue.main.async { [weak self] in self?.drainOutput(token: token) } }
    }
    private func drainOutput(token: UUID) {
        lock.lock()
        guard active, generation == token else { lock.unlock(); return }
        let packets = pendingOutput; pendingOutput.removeAll(); outputScheduled = false; lock.unlock()
        for packet in packets {
            lock.lock(); let valid = active && generation == token; lock.unlock()
            guard valid else { return }
            onFrame?(packet)
        }
    }
    private func fail(_ reason: String, token: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let valid = self.active && self.generation == token; self.lock.unlock()
            guard valid else { return }
            let callback = self.onFailure; self.stop(); callback?(reason)
        }
    }
    /// Never feed the received virtual microphone back to the other Mac. Read
    /// the actual CoreAudio default device UID; no device selection is changed.
    private static func rejectVirtualDefaultInput() throws {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { throw BridgeError.invalid("No default microphone input device") }
        for selector in [kAudioDevicePropertyDeviceUID, kAudioObjectPropertyName] {
            var value: CFString = "" as CFString
            var valueSize = UInt32(MemoryLayout<CFString>.size)
            var field = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            let status = withUnsafeMutablePointer(to: &value) { pointer in
                AudioObjectGetPropertyData(device, &field, 0, nil, &valueSize, pointer)
            }
            guard status == noErr else {
                throw BridgeError.invalid("Cannot verify microphone input device")
            }
            let name = (value as String).lowercased()
            if name.contains("keybridge") || name.contains("键桥") {
                throw BridgeError.invalid("Choose a physical microphone as the default input before sharing. KeyBridge Microphone cannot capture itself.")
            }
        }
    }
    deinit {
        if let observer = configurationObserver { NotificationCenter.default.removeObserver(observer) }
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0) }
        engine?.stop()
    }
}
