// SPDX-License-Identifier: MIT
#pragma once
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

#define KB_AUDIO_DEVICE_UID "org.keybridge.audio.microphone"
#define KB_AUDIO_WRITE_SELECTOR ((AudioObjectPropertySelector)0x6b627772) /* kbwr */
#define KB_AUDIO_STATUS_SELECTOR ((AudioObjectPropertySelector)0x6b627374) /* kbst */
#define KB_AUDIO_MAGIC UINT32_C(0x314d424b) /* little-endian bytes KBM1 */
#define KB_AUDIO_PROTOCOL_VERSION UINT32_C(1)
#define KB_AUDIO_SAMPLE_RATE 48000
#define KB_AUDIO_MAX_PACKET_FRAMES 1920
#define KB_AUDIO_FLAG_BEGIN UINT32_C(1)
#define KB_AUDIO_FLAG_END UINT32_C(2)

// All integers and Float32 samples are little-endian. Header is exactly 32 bytes.
// Send a CFDataRef containing this header and frameCount Float32 values via
// AudioObjectSetPropertyData(device, { 'kbwr', global, main }, 0, NULL,
//                            sizeof(CFDataRef), &data).
typedef struct {
    uint32_t magic;
    uint32_t version;
    uint64_t session;
    uint64_t sequence;
    uint32_t frameCount;
    uint32_t flags;
} KBAudioPacketHeader;

#ifdef __cplusplus
extern "C" {
#endif
// Small app-side CoreAudio client, optional for Swift callers. Each handle is serial-use.
typedef struct KBAudioWriter KBAudioWriter;
OSStatus KBAudioWriterOpen(KBAudioWriter **outWriter);
OSStatus KBAudioWriterPush(KBAudioWriter *writer, const float *samples, uint32_t frameCount);
void KBAudioWriterClose(KBAudioWriter *writer);
#ifdef __cplusplus
}
#endif
