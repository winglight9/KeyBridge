// SPDX-License-Identifier: MIT
#include "include/KeyBridgeAudioIPC.h"
#include <stdlib.h>
#include <string.h>
struct KBAudioWriter { AudioObjectID device; uint64_t session, sequence; };
static OSStatus sendPacket(KBAudioWriter *w, const float *samples, uint32_t frames, uint32_t flags) {
    if (!w || frames > KB_AUDIO_MAX_PACKET_FRAMES || (frames && !samples)) return kAudioHardwareIllegalOperationError;
    uint8_t bytes[32 + KB_AUDIO_MAX_PACKET_FRAMES * sizeof(float)];
    KBAudioPacketHeader header = {KB_AUDIO_MAGIC, KB_AUDIO_PROTOCOL_VERSION, w->session, w->sequence++, frames, flags};
    memcpy(bytes, &header, sizeof(header)); if (frames) memcpy(bytes + 32, samples, frames * sizeof(float));
    CFDataRef data = CFDataCreate(NULL, bytes, 32 + frames * sizeof(float));
    if (!data) return kAudioHardwareUnspecifiedError;
    AudioObjectPropertyAddress property = {KB_AUDIO_WRITE_SELECTOR, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    OSStatus status = AudioObjectSetPropertyData(w->device, &property, 0, NULL, sizeof(data), &data);
    CFRelease(data); return status;
}
OSStatus KBAudioWriterOpen(KBAudioWriter **out) {
    if (!out) return kAudioHardwareIllegalOperationError; *out = NULL;
    CFStringRef uid = CFSTR(KB_AUDIO_DEVICE_UID); AudioObjectID device = kAudioObjectUnknown;
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyTranslateUIDToDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 size = sizeof(device);
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, sizeof(uid), &uid, &size, &device);
    if (status) return status; if (device == kAudioObjectUnknown) return kAudioHardwareBadDeviceError;
    KBAudioWriter *w = calloc(1, sizeof(*w)); if (!w) return kAudioHardwareUnspecifiedError;
    w->device = device; do { arc4random_buf(&w->session, sizeof(w->session)); } while (!w->session);
    status = sendPacket(w, NULL, 0, KB_AUDIO_FLAG_BEGIN);
    if (status) { free(w); return status; } *out = w; return noErr;
}
OSStatus KBAudioWriterPush(KBAudioWriter *w, const float *samples, uint32_t frames) {
    if (!frames) return kAudioHardwareIllegalOperationError;
    return sendPacket(w, samples, frames, 0);
}
void KBAudioWriterClose(KBAudioWriter *w) { if (w) { (void)sendPacket(w, NULL, 0, KB_AUDIO_FLAG_END); free(w); } }
