import Foundation

/// Experimental microphone protocol v2: 20 ms of mono, signed little-endian Int16 PCM.
/// Audio is a separate message payload and never an InputPacket.
public struct AudioPacket: Codable, Equatable {
    public static let version = 2
    public static let sampleRate = 48_000
    public static let channelCount = 1
    public static let samplesPerFrame = 960
    public static let bytesPerFrame = samplesPerFrame * MemoryLayout<Int16>.size
    public static let sampleFormat = "pcm_s16le"

    public var streamID: String
    /// Control messages use zero; frames start at one and may skip dropped frames.
    public var sequence: UInt64
    public var sampleRate: Int
    public var channelCount: Int
    public var samplesPerFrame: Int
    public var sampleFormat: String
    /// Absent for start/ready/stop/error, exactly bytesPerFrame for an audioFrame.
    public var pcm: Data?

    public init(streamID: String, sequence: UInt64 = 0, pcm: Data? = nil,
                sampleRate: Int = AudioPacket.sampleRate,
                channelCount: Int = AudioPacket.channelCount,
                samplesPerFrame: Int = AudioPacket.samplesPerFrame,
                sampleFormat: String = AudioPacket.sampleFormat) {
        self.streamID = streamID; self.sequence = sequence; self.pcm = pcm
        self.sampleRate = sampleRate; self.channelCount = channelCount
        self.samplesPerFrame = samplesPerFrame; self.sampleFormat = sampleFormat
    }
    public var isValidFormat: Bool {
        UUID(uuidString: streamID) != nil && sampleRate == Self.sampleRate &&
        channelCount == Self.channelCount && samplesPerFrame == Self.samplesPerFrame &&
        sampleFormat == Self.sampleFormat
    }
    public var isValidControl: Bool { isValidFormat && sequence == 0 && pcm == nil }
    public var isValidFrame: Bool {
        isValidFormat && sequence > 0 && pcm?.count == Self.bytesPerFrame
    }
    public var isValid: Bool { isValidControl || isValidFrame }
}

extension Message.Kind {
    public var isAudio: Bool {
        switch self {
        case .audioStart, .audioFrame, .audioStop, .audioReady, .audioError, .audioRequest, .audioPreparing, .audioActive: return true
        default: return false
        }
    }
}
