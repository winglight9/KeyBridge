# App ↔ HAL contract (protocol 1)

The virtual input device UID is `org.keybridge.audio.microphone`. Find it with
`kAudioHardwarePropertyTranslateUIDToDevice`, using a CFStringRef qualifier as
specified by CoreAudio. Its display name is **KeyBridge Microphone** (Chinese
bundle localization: **键桥麦克风**). Input only: 48,000 Hz / mono / packed Float32.
It never becomes the default input automatically.

## Swift integration — no extra linker setup required

Write a `CFData` packet to the device's global/main custom property selector
`0x6b627772` (`kbwr`). Property data is a **CFDataRef pointer**, so pass
`MemoryLayout<CFData>.size` and `&data` to `AudioObjectSetPropertyData`.

Packet, all little endian:

| Byte | Type | Value |
| --- | --- | --- |
| 0 | UInt32 | `0x314d424b` (`KBM1` bytes) |
| 4 | UInt32 | protocol 1 |
| 8 | UInt64 | random nonzero session ID, constant until end |
| 16 | UInt64 | sequence: BEGIN=0; increment for every PUSH/END |
| 24 | UInt32 | frameCount: 0 for BEGIN/END; 1…1920 for PUSH |
| 28 | UInt32 | flags: BEGIN=1; PUSH=0; END=2 |
| 32 | Float32[frameCount] | mono PCM, finite values, driver clamps to [-1,1] |

Use a serial non-realtime queue. BEGIN clears the driver ring, authenticates the
calling process, and claims the writer. PUSH accepts the matching process/session
and strictly increasing sequence. END immediately silences and clears buffered
samples. Call END on forwarding stop, disconnect, local capture stop, or error.
Use packets around 480 or 960 frames (10–20 ms); do not send during disconnection.

Optional C convenience ABI: `include/KeyBridgeAudioIPC.h` + `KBAudioWriter.c`.
`Open` finds the device and sends BEGIN; `Push` sends PCM; `Close` sends END and
frees the handle. OSStatus is returned unchanged; show failure to the user.

## Safety and platform choices

This uses Apple's AudioServerPlugIn custom-property IPC, whose caller PID is
provided by the audio server. The driver owns its atomically accessed ring;
there is no world-writable shared-memory object, socket, temporary PCM file, or
IPC permission that lets an unrelated user inject audio.

BEGIN requires the current console user's process, exact installed executable
path `/Applications/KeyBridge.app/Contents/MacOS/KeyBridge`, valid signature, and
the installed app's designated code requirement. The current console UID and writer PID/start-time are
checked on packets to detect PID reuse. A new BEGIN replaces only the same
eligible application's writer. Unsigned clients and generic audio apps may read
this microphone but cannot write PCM.

The driver emits silence before BEGIN, without PCM, after END, and when no packet
arrives for 250 ms. Sequence/session checking prevents a delayed old stream from
reopening a stopped stream. A new session clears the ring. ReadInput uses tagged
sample-time slots rather than consuming one global cursor, so simultaneous audio
clients receive the same samples.

The app must retain its normal microphone permission for *capture*. This driver
provides an input device for receiving applications; each receiving application's
macOS microphone privacy rules still apply. It does not grant microphone access.

This IPC intentionally avoids POSIX shared memory: an AudioServerPlugIn runs in
the audio server's identity, which differs from the GUI user's identity. A fixed
0600 shm owned by that identity is not writable by the app; changing it to 0666
would permit other local users to inject audio. CoreAudio's authenticated custom
property transport carries small 10–20 ms PCM blocks into the driver ring instead.

## Primary references

- Apple, Creating an Audio Server Driver Plug-in:
  https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in
- Apple SDK `CoreAudio/AudioServerPlugIn.h`: custom-property type marshalling,
  `SetPropertyData` caller PID, `AudioServerPlugInDriverInterface`, ReadInput.
- Apple `Security/SecCode.h` and `SecStaticCode.h`: guest process identity,
  designated requirements, code validity.

Implementation is original MIT-licensed code. No third-party driver source copied.
