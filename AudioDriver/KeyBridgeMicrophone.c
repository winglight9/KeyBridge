// SPDX-License-Identifier: MIT
// Original input-only AudioServerPlugIn. Public interface follows Apple's CoreAudio SDK.
#include "include/KeyBridgeAudioIPC.h"
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CFPlugInCOM.h>
#include <Security/Security.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <math.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

_Static_assert(sizeof(KBAudioPacketHeader) == 32, "IPC header layout");
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2 && ATOMIC_INT_LOCK_FREE == 2, "Realtime ring requires lock-free atomics");
enum { kPlugin = kAudioObjectPlugInObject, kDevice = 2, kInput = 3, kRingFrames = 8192, kClockPeriod = 512 };
static AudioServerPlugInHostRef gHost;
static _Atomic UInt32 gRefs = 1, gRunning = 0;
static _Atomic bool gStreamActive = true, gEnabled = false;
static _Atomic UInt64 gEpoch = 1, gLastPacket = 0;
static UInt64 gAnchor;
static double gTicksPerFrame;
static pthread_mutex_t gWriterLock = PTHREAD_MUTEX_INITIALIZER;
static pid_t gWriterPID;
static UInt64 gWriterStartSec, gWriterStartUSec, gSession, gSequence, gWriteFrame;
static uid_t gWriterUID;
typedef struct { _Atomic UInt64 frame, epoch; _Atomic UInt32 bits; } RingSlot;
static RingSlot gRing[kRingFrames];
static AudioServerPlugInDriverRef gDriver;

static bool validObject(AudioObjectID o) { return o == kPlugin || o == kDevice || o == kInput; }
static AudioStreamBasicDescription format(void) {
    return (AudioStreamBasicDescription){ .mSampleRate = KB_AUDIO_SAMPLE_RATE,
        .mFormatID = kAudioFormatLinearPCM, .mFormatFlags = kAudioFormatFlagsNativeFloatPacked,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4,
        .mChannelsPerFrame = 1, .mBitsPerChannel = 32 };
}
static UInt64 nowFrame(UInt64 host) {
    return host >= gAnchor ? (UInt64)((double)(host - gAnchor) / gTicksPerFrame) : 0;
}
static void clearRing(void) {
    atomic_store_explicit(&gEnabled, false, memory_order_release);
    atomic_fetch_add_explicit(&gEpoch, 1, memory_order_acq_rel);
    for (unsigned i = 0; i < kRingFrames; ++i) atomic_store_explicit(&gRing[i].frame, 0, memory_order_release);
    atomic_store_explicit(&gLastPacket, 0, memory_order_release);
    gWriteFrame = 0;
}
static bool processInfo(pid_t pid, struct proc_bsdinfo *out) {
    return pid > 0 && proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, out, sizeof(*out)) == sizeof(*out);
}
static bool authenticatedWriter(pid_t pid, struct proc_bsdinfo *info) {
    if (!processInfo(pid, info)) return false;
    uid_t consoleUID = (uid_t)-1; gid_t consoleGID = 0;
    CFStringRef console = SCDynamicStoreCopyConsoleUser(NULL, &consoleUID, &consoleGID);
    if (console) CFRelease(console);
    if (consoleUID == (uid_t)-1 || consoleUID == 0 || info->pbi_uid != consoleUID) return false;
    char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
    if (proc_pidpath(pid, path, sizeof(path)) <= 0 ||
        strcmp(path, "/Applications/KeyBridge.app/Contents/MacOS/KeyBridge") != 0) return false;
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, CFSTR("/Applications/KeyBridge.app"), kCFURLPOSIXPathStyle, true);
    SecStaticCodeRef installed = NULL; SecRequirementRef requirement = NULL; SecCodeRef guest = NULL;
    CFNumberRef pidNumber = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    const void *keys[] = { kSecGuestAttributePid }; const void *values[] = { pidNumber };
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    OSStatus status = SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &installed);
    if (status == noErr) status = SecStaticCodeCheckValidity(installed, kSecCSStrictValidate, NULL);
    if (status == noErr) status = SecCodeCopyDesignatedRequirement((SecCodeRef)installed, kSecCSDefaultFlags, &requirement);
    if (status == noErr) status = SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, &guest);
    if (status == noErr) status = SecCodeCheckValidity(guest, kSecCSStrictValidate, requirement);
    if (guest) CFRelease(guest); if (requirement) CFRelease(requirement); if (installed) CFRelease(installed);
    CFRelease(attributes); CFRelease(pidNumber); CFRelease(url);
    return status == noErr;
}
static bool sameWriter(pid_t pid) {
    struct proc_bsdinfo info; struct stat console;
    if (stat("/dev/console", &console) != 0 || console.st_uid != gWriterUID) return false;
    return pid == gWriterPID && processInfo(pid, &info) && info.pbi_uid == gWriterUID &&
        info.pbi_start_tvsec == gWriterStartSec && info.pbi_start_tvusec == gWriterStartUSec;
}
static OSStatus writePacket(pid_t pid, CFDataRef data) {
    if (!data || CFGetTypeID(data) != CFDataGetTypeID() || CFDataGetLength(data) < 32) return kAudioHardwareBadPropertySizeError;
    KBAudioPacketHeader h; memcpy(&h, CFDataGetBytePtr(data), sizeof(h));
    if (h.magic != KB_AUDIO_MAGIC || h.version != KB_AUDIO_PROTOCOL_VERSION || h.session == 0 ||
        h.frameCount > KB_AUDIO_MAX_PACKET_FRAMES || CFDataGetLength(data) != 32 + h.frameCount * sizeof(float) ||
        (h.flags != 0 && h.flags != KB_AUDIO_FLAG_BEGIN && h.flags != KB_AUDIO_FLAG_END) ||
        ((h.flags != 0) != (h.frameCount == 0))) return kAudioHardwareIllegalOperationError;
    pthread_mutex_lock(&gWriterLock);
    OSStatus status = noErr;
    if (h.flags == KB_AUDIO_FLAG_BEGIN) {
        struct proc_bsdinfo info;
        if (h.sequence != 0 || !authenticatedWriter(pid, &info)) { status = kAudioHardwareIllegalOperationError; goto done; }
        clearRing(); gWriterPID = pid; gWriterUID = info.pbi_uid;
        gWriterStartSec = info.pbi_start_tvsec; gWriterStartUSec = info.pbi_start_tvusec;
        gSession = h.session; gSequence = 0;
        goto done;
    }
    if (pid == gWriterPID && !sameWriter(pid)) {
        clearRing(); gSession = 0; gWriterPID = 0;
        status = kAudioHardwareIllegalOperationError; goto done;
    }
    if (pid != gWriterPID || h.session != gSession || h.sequence != gSequence + 1) {
        status = kAudioHardwareIllegalOperationError; goto done;
    }
    gSequence = h.sequence;
    if (h.flags == KB_AUDIO_FLAG_END) { clearRing(); gSession = 0; gWriterPID = 0; goto done; }
    UInt64 host = mach_absolute_time(), playhead = nowFrame(host);
    // Keep at most 80 ms ahead. After a stall start a fresh 20 ms prebuffer.
    if (gWriteFrame < playhead + 128 || gWriteFrame > playhead + 3840) {
        clearRing(); gWriteFrame = playhead + 960;
    }
    UInt64 epoch = atomic_load_explicit(&gEpoch, memory_order_acquire);
    const UInt8 *bytes = CFDataGetBytePtr(data) + 32;
    for (UInt32 i = 0; i < h.frameCount; ++i) {
        float sample; memcpy(&sample, bytes + i * sizeof(sample), sizeof(sample));
        if (!isfinite(sample)) sample = 0;
        sample = fmaxf(-1.0f, fminf(1.0f, sample));
        UInt32 bits; memcpy(&bits, &sample, sizeof(bits));
        UInt64 frame = gWriteFrame + i; RingSlot *slot = &gRing[frame % kRingFrames];
        atomic_store_explicit(&slot->frame, 0, memory_order_release);
        atomic_store_explicit(&slot->bits, bits, memory_order_relaxed);
        atomic_store_explicit(&slot->epoch, epoch, memory_order_relaxed);
        atomic_store_explicit(&slot->frame, frame + 1, memory_order_release);
    }
    gWriteFrame += h.frameCount;
    atomic_store_explicit(&gLastPacket, host, memory_order_release);
    atomic_store_explicit(&gEnabled, true, memory_order_release);
done:
    pthread_mutex_unlock(&gWriterLock); return status;
}

static HRESULT query(void *driver, REFIID uuid, LPVOID *out) {
    if (!out) return E_POINTER; *out = NULL;
    CFUUIDRef id = CFUUIDCreateFromUUIDBytes(NULL, uuid);
    bool match = CFEqual(id, IUnknownUUID) || CFEqual(id, kAudioServerPlugInDriverInterfaceUUID); CFRelease(id);
    if (!match) return E_NOINTERFACE;
    atomic_fetch_add(&gRefs, 1); *out = driver; return S_OK;
}
static ULONG addRef(void *driver) { (void)driver; return atomic_fetch_add(&gRefs, 1) + 1; }
static ULONG releaseRef(void *driver) { (void)driver; UInt32 old = atomic_load(&gRefs); while (old > 1 && !atomic_compare_exchange_weak(&gRefs, &old, old - 1)) {} return old > 1 ? old - 1 : 1; }
static OSStatus initialize(AudioServerPlugInDriverRef d, AudioServerPlugInHostRef host) {
    (void)d; gHost = host; mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    gTicksPerFrame = (1e9 / KB_AUDIO_SAMPLE_RATE) * tb.denom / tb.numer; gAnchor = mach_absolute_time(); return noErr;
}
static OSStatus createDevice(AudioServerPlugInDriverRef d, CFDictionaryRef desc, const AudioServerPlugInClientInfo *client, AudioObjectID *out) {
    (void)d; (void)desc; (void)client; if (out) *out = kAudioObjectUnknown; return kAudioHardwareUnsupportedOperationError;
}
static OSStatus destroyDevice(AudioServerPlugInDriverRef d, AudioObjectID o) { (void)d; (void)o; return kAudioHardwareUnsupportedOperationError; }
static OSStatus addClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo *client) { (void)d; (void)client; return o == kDevice ? noErr : kAudioHardwareBadObjectError; }
static OSStatus removeClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo *client) { return addClient(d, o, client); }
static OSStatus configuration(AudioServerPlugInDriverRef d, AudioObjectID o, UInt64 action, void *info) { (void)d; (void)action; (void)info; return o == kDevice ? noErr : kAudioHardwareBadObjectError; }

static bool inputScope(const AudioObjectPropertyAddress *a) { return a->mScope == kAudioObjectPropertyScopeGlobal || a->mScope == kAudioObjectPropertyScopeInput; }
static Boolean hasProperty(AudioServerPlugInDriverRef d, AudioObjectID o, pid_t pid, const AudioObjectPropertyAddress *a) {
    (void)d; (void)pid;
    if (!a || !validObject(o) || a->mElement != kAudioObjectPropertyElementMain) return false;
    switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName: case kAudioObjectPropertyManufacturer: case kAudioObjectPropertyOwnedObjects: return true;
    }
    if (o == kPlugin) switch (a->mSelector) {
        case kAudioPlugInPropertyBundleID: case kAudioPlugInPropertyDeviceList:
        case kAudioPlugInPropertyTranslateUIDToDevice: case kAudioPlugInPropertyResourceBundle: return true;
    }
    if (o == kDevice) switch (a->mSelector) {
        case kAudioObjectPropertyCustomPropertyInfoList: case KB_AUDIO_WRITE_SELECTOR: case KB_AUDIO_STATUS_SELECTOR:
        case kAudioDevicePropertyDeviceUID: case kAudioDevicePropertyModelUID: case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices: case kAudioDevicePropertyClockDomain: case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning: case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset: case kAudioDevicePropertyStreams: case kAudioObjectPropertyControlList:
        case kAudioDevicePropertyNominalSampleRate: case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyIsHidden: case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyPreferredChannelsForStereo: case kAudioDevicePropertyPreferredChannelLayout:
        case kAudioDevicePropertyStreamConfiguration: case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyBufferFrameSizeRange: case kAudioDevicePropertyUsesVariableBufferFrameSizes:
        case kAudioDevicePropertyClockAlgorithm: case kAudioDevicePropertyClockIsStable: return true;
    }
    if (o == kInput) switch (a->mSelector) {
        case kAudioStreamPropertyIsActive: case kAudioStreamPropertyDirection: case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel: case kAudioStreamPropertyLatency: case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: return true;
    }
    return false;
}
static OSStatus isSettable(AudioServerPlugInDriverRef d, AudioObjectID o, pid_t pid, const AudioObjectPropertyAddress *a, Boolean *out) {
    if (!out) return kAudioHardwareIllegalOperationError;
    if (!hasProperty(d, o, pid, a)) return kAudioHardwareUnknownPropertyError;
    *out = (o == kDevice && (a->mSelector == KB_AUDIO_WRITE_SELECTOR || a->mSelector == kAudioDevicePropertyNominalSampleRate || a->mSelector == kAudioDevicePropertyBufferFrameSize)) ||
        (o == kInput && (a->mSelector == kAudioStreamPropertyIsActive || a->mSelector == kAudioStreamPropertyVirtualFormat || a->mSelector == kAudioStreamPropertyPhysicalFormat));
    return noErr;
}
static UInt32 propertySize(AudioObjectID o, const AudioObjectPropertyAddress *a) {
    switch (a->mSelector) {
        case kAudioObjectPropertyName: case kAudioObjectPropertyManufacturer: case kAudioPlugInPropertyBundleID:
        case kAudioPlugInPropertyResourceBundle: case kAudioDevicePropertyDeviceUID: case kAudioDevicePropertyModelUID:
        case KB_AUDIO_WRITE_SELECTOR: case KB_AUDIO_STATUS_SELECTOR: return sizeof(CFTypeRef);
        case kAudioObjectPropertyOwnedObjects:
            return o == kPlugin ? sizeof(AudioObjectID) : o == kDevice && inputScope(a) ? sizeof(AudioObjectID) : 0;
        case kAudioPlugInPropertyDeviceList: case kAudioDevicePropertyRelatedDevices: return sizeof(AudioObjectID);
        case kAudioDevicePropertyStreams: return inputScope(a) ? sizeof(AudioObjectID) : 0;
        case kAudioObjectPropertyControlList: return 0;
        case kAudioObjectPropertyCustomPropertyInfoList: return 2 * sizeof(AudioServerPlugInCustomPropertyInfo);
        case kAudioDevicePropertyNominalSampleRate: return sizeof(Float64);
        case kAudioDevicePropertyAvailableNominalSampleRates: case kAudioDevicePropertyBufferFrameSizeRange: return sizeof(AudioValueRange);
        case kAudioDevicePropertyPreferredChannelsForStereo: return 2 * sizeof(UInt32);
        case kAudioDevicePropertyPreferredChannelLayout: return offsetof(AudioChannelLayout, mChannelDescriptions) + sizeof(AudioChannelDescription);
        case kAudioDevicePropertyStreamConfiguration: return offsetof(AudioBufferList, mBuffers) + (inputScope(a) ? sizeof(AudioBuffer) : 0);
        case kAudioStreamPropertyVirtualFormat: case kAudioStreamPropertyPhysicalFormat: return sizeof(AudioStreamBasicDescription);
        case kAudioStreamPropertyAvailableVirtualFormats: case kAudioStreamPropertyAvailablePhysicalFormats: return sizeof(AudioStreamRangedDescription);
        default: return sizeof(UInt32);
    }
}
static OSStatus getSize(AudioServerPlugInDriverRef d, AudioObjectID o, pid_t pid, const AudioObjectPropertyAddress *a, UInt32 qs, const void *q, UInt32 *out) {
    (void)qs; (void)q; if (!out) return kAudioHardwareIllegalOperationError;
    if (!hasProperty(d, o, pid, a)) return kAudioHardwareUnknownPropertyError;
    *out = propertySize(o, a); return noErr;
}
#define RETURN_VALUE(TYPE, VALUE) do { TYPE value = (VALUE); memcpy(out, &value, sizeof(value)); return noErr; } while (0)
static OSStatus getProperty(AudioServerPlugInDriverRef d, AudioObjectID o, pid_t pid, const AudioObjectPropertyAddress *a, UInt32 qs, const void *q, UInt32 capacity, UInt32 *used, void *out) {
    if (!used || !hasProperty(d, o, pid, a)) return kAudioHardwareUnknownPropertyError;
    UInt32 size = propertySize(o, a); if (capacity < size || (size && !out)) return kAudioHardwareBadPropertySizeError;
    *used = size; if (!size) return noErr; memset(out, 0, size);
    switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: RETURN_VALUE(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: RETURN_VALUE(AudioClassID, o == kPlugin ? kAudioPlugInClassID : o == kDevice ? kAudioDeviceClassID : kAudioStreamClassID);
        case kAudioObjectPropertyOwner: RETURN_VALUE(AudioObjectID, o == kPlugin ? kAudioObjectSystemObject : o == kDevice ? kPlugin : kDevice);
        case kAudioObjectPropertyManufacturer: RETURN_VALUE(CFStringRef, CFRetain(CFSTR("KeyBridge")));
        case kAudioObjectPropertyName: {
            CFStringRef name = o == kInput ? CFSTR("Microphone Input") : o == kPlugin ? CFSTR("KeyBridge Audio") : CFSTR("KeyBridge Microphone");
            CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR("org.keybridge.audio.microphone"));
            CFStringRef localized = bundle ? CFBundleCopyLocalizedString(bundle, name, name, NULL) : CFRetain(name);
            RETURN_VALUE(CFStringRef, localized);
        }
        case kAudioObjectPropertyOwnedObjects: RETURN_VALUE(AudioObjectID, o == kPlugin ? kDevice : kInput);
        case kAudioPlugInPropertyBundleID: RETURN_VALUE(CFStringRef, CFRetain(CFSTR("org.keybridge.audio.microphone")));
        case kAudioPlugInPropertyResourceBundle: RETURN_VALUE(CFStringRef, CFRetain(CFSTR("")));
        case kAudioPlugInPropertyDeviceList: case kAudioDevicePropertyRelatedDevices: RETURN_VALUE(AudioObjectID, kDevice);
        case kAudioPlugInPropertyTranslateUIDToDevice: {
            if (qs != sizeof(CFStringRef) || !q) return kAudioHardwareBadPropertySizeError;
            CFStringRef uid = *(const CFStringRef *)q;
            RETURN_VALUE(AudioObjectID, uid && CFEqual(uid, CFSTR(KB_AUDIO_DEVICE_UID)) ? kDevice : kAudioObjectUnknown);
        }
        case kAudioDevicePropertyDeviceUID: RETURN_VALUE(CFStringRef, CFRetain(CFSTR(KB_AUDIO_DEVICE_UID)));
        case kAudioDevicePropertyModelUID: RETURN_VALUE(CFStringRef, CFRetain(CFSTR("org.keybridge.audio.microphone.model.v1")));
        case kAudioDevicePropertyTransportType: RETURN_VALUE(UInt32, kAudioDeviceTransportTypeVirtual);
        case kAudioDevicePropertyClockDomain: case kAudioDevicePropertyIsHidden: case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset: case kAudioDevicePropertyUsesVariableBufferFrameSizes: RETURN_VALUE(UInt32, 0);
        case kAudioDevicePropertyDeviceIsAlive: case kAudioDevicePropertyClockIsStable: RETURN_VALUE(UInt32, 1);
        case kAudioDevicePropertyClockAlgorithm: RETURN_VALUE(UInt32, kAudioDeviceClockAlgorithmSimpleIIR);
        case kAudioDevicePropertyDeviceIsRunning: RETURN_VALUE(UInt32, atomic_load(&gRunning) != 0);
        case kAudioDevicePropertyDeviceCanBeDefaultDevice: RETURN_VALUE(UInt32, a->mScope == kAudioObjectPropertyScopeInput);
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: RETURN_VALUE(UInt32, 0);
        case kAudioDevicePropertyStreams: RETURN_VALUE(AudioObjectID, kInput);
        case kAudioDevicePropertyNominalSampleRate: RETURN_VALUE(Float64, KB_AUDIO_SAMPLE_RATE);
        case kAudioDevicePropertyAvailableNominalSampleRates: { AudioValueRange v = {KB_AUDIO_SAMPLE_RATE, KB_AUDIO_SAMPLE_RATE}; memcpy(out, &v, sizeof(v)); return noErr; }
        case kAudioDevicePropertyZeroTimeStampPeriod: RETURN_VALUE(UInt32, kClockPeriod);
        case kAudioDevicePropertyBufferFrameSize: RETURN_VALUE(UInt32, 512);
        case kAudioDevicePropertyBufferFrameSizeRange: { AudioValueRange v = {512, 512}; memcpy(out, &v, sizeof(v)); return noErr; }
        case kAudioDevicePropertyPreferredChannelsForStereo: { UInt32 v[2] = {1, 1}; memcpy(out, v, sizeof(v)); return noErr; }
        case kAudioDevicePropertyPreferredChannelLayout: {
            AudioChannelLayout *v = out; v->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
            v->mNumberChannelDescriptions = 1; v->mChannelDescriptions[0].mChannelLabel = kAudioChannelLabel_Mono; return noErr;
        }
        case kAudioDevicePropertyStreamConfiguration: {
            AudioBufferList *v = out; v->mNumberBuffers = inputScope(a) ? 1 : 0;
            if (v->mNumberBuffers) v->mBuffers[0].mNumberChannels = 1; return noErr;
        }
        case kAudioStreamPropertyIsActive: RETURN_VALUE(UInt32, atomic_load(&gStreamActive));
        case kAudioStreamPropertyDirection: case kAudioStreamPropertyStartingChannel: RETURN_VALUE(UInt32, 1);
        case kAudioStreamPropertyTerminalType: RETURN_VALUE(UInt32, kAudioStreamTerminalTypeMicrophone);
        case kAudioStreamPropertyVirtualFormat: case kAudioStreamPropertyPhysicalFormat: { AudioStreamBasicDescription v = format(); memcpy(out, &v, sizeof(v)); return noErr; }
        case kAudioStreamPropertyAvailableVirtualFormats: case kAudioStreamPropertyAvailablePhysicalFormats: {
            AudioStreamRangedDescription v = {.mFormat = format(), .mSampleRateRange = {KB_AUDIO_SAMPLE_RATE, KB_AUDIO_SAMPLE_RATE}};
            memcpy(out, &v, sizeof(v)); return noErr;
        }
        case kAudioObjectPropertyCustomPropertyInfoList: {
            AudioServerPlugInCustomPropertyInfo v[2] = {
                { KB_AUDIO_WRITE_SELECTOR, kAudioServerPlugInCustomPropertyDataTypeCFPropertyList, kAudioServerPlugInCustomPropertyDataTypeNone },
                { KB_AUDIO_STATUS_SELECTOR, kAudioServerPlugInCustomPropertyDataTypeCFPropertyList, kAudioServerPlugInCustomPropertyDataTypeNone }
            }; memcpy(out, v, sizeof(v)); return noErr;
        }
        case KB_AUDIO_WRITE_SELECTOR: { CFDataRef v = CFDataCreate(NULL, NULL, 0); RETURN_VALUE(CFDataRef, v); }
        case KB_AUDIO_STATUS_SELECTOR: {
            const void *keys[] = { CFSTR("protocol"), CFSTR("format"), CFSTR("receiving") };
            int protocol = 1; CFNumberRef version = CFNumberCreate(NULL, kCFNumberIntType, &protocol);
            UInt64 last = atomic_load(&gLastPacket), now = mach_absolute_time();
            bool active = atomic_load(&gEnabled) && last && now >= last && (double)(now - last) < gTicksPerFrame * KB_AUDIO_SAMPLE_RATE / 4;
            const void *values[] = { version, CFSTR("48000/mono/float32"), active ? kCFBooleanTrue : kCFBooleanFalse };
            CFDictionaryRef v = CFDictionaryCreate(NULL, keys, values, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFRelease(version); RETURN_VALUE(CFDictionaryRef, v);
        }
    }
    return kAudioHardwareUnknownPropertyError;
}
static OSStatus setProperty(AudioServerPlugInDriverRef d, AudioObjectID o, pid_t pid, const AudioObjectPropertyAddress *a, UInt32 qs, const void *q, UInt32 size, const void *data) {
    (void)qs; (void)q; Boolean settable = false; OSStatus status = isSettable(d, o, pid, a, &settable);
    if (status || !settable || !data) return status ? status : kAudioHardwareIllegalOperationError;
    if (a->mSelector == KB_AUDIO_WRITE_SELECTOR) {
        if (size != sizeof(CFDataRef)) return kAudioHardwareBadPropertySizeError;
        return writePacket(pid, *(const CFDataRef *)data);
    }
    if (a->mSelector == kAudioStreamPropertyIsActive) {
        if (size != sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
        atomic_store(&gStreamActive, *(const UInt32 *)data != 0);
    } else if (a->mSelector == kAudioDevicePropertyNominalSampleRate) {
        if (size != sizeof(Float64)) return kAudioHardwareBadPropertySizeError;
        if (*(const Float64 *)data != KB_AUDIO_SAMPLE_RATE) return kAudioHardwareIllegalOperationError;
    } else if (a->mSelector == kAudioDevicePropertyBufferFrameSize) {
        if (size != sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
        if (*(const UInt32 *)data != 512) return kAudioHardwareIllegalOperationError;
    } else {
        if (size != sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
        AudioStreamBasicDescription f = format(); if (memcmp(data, &f, sizeof(f)) != 0) return kAudioDeviceUnsupportedFormatError;
    }
    if (gHost) gHost->PropertiesChanged(gHost, o, 1, a); return noErr;
}
static OSStatus startIO(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 client) {
    (void)d; (void)client; if (o != kDevice) return kAudioHardwareBadObjectError;
    atomic_fetch_add(&gRunning, 1); return noErr;
}
static OSStatus stopIO(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 client) {
    (void)d; (void)client; if (o != kDevice) return kAudioHardwareBadObjectError;
    UInt32 old = atomic_load(&gRunning); while (old && !atomic_compare_exchange_weak(&gRunning, &old, old - 1)) {} return noErr;
}
static OSStatus zeroTime(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 client, Float64 *sample, UInt64 *host, UInt64 *seed) {
    (void)d; (void)client; if (o != kDevice) return kAudioHardwareBadObjectError;
    if (!sample || !host || !seed) return kAudioHardwareIllegalOperationError;
    UInt64 frame = nowFrame(mach_absolute_time()) / kClockPeriod * kClockPeriod;
    *sample = (Float64)frame; *host = gAnchor + (UInt64)((double)frame * gTicksPerFrame); *seed = 1; return noErr;
}
static OSStatus willIO(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 client, UInt32 operation, Boolean *will, Boolean *inPlace) {
    (void)d; (void)client; if (o != kDevice) return kAudioHardwareBadObjectError;
    if (will) *will = operation == kAudioServerPlugInIOOperationReadInput; if (inPlace) *inPlace = true; return noErr;
}
static OSStatus boundaryIO(AudioServerPlugInDriverRef d, AudioObjectID o, UInt32 client, UInt32 op, UInt32 count, const AudioServerPlugInIOCycleInfo *cycle) {
    (void)d; (void)client; (void)op; (void)count; (void)cycle; return o == kDevice ? noErr : kAudioHardwareBadObjectError;
}
static OSStatus doIO(AudioServerPlugInDriverRef d, AudioObjectID o, AudioObjectID stream, UInt32 client, UInt32 op, UInt32 count, const AudioServerPlugInIOCycleInfo *cycle, void *main, void *secondary) {
    (void)d; (void)client; (void)secondary;
    if (o != kDevice || stream != kInput) return kAudioHardwareBadObjectError;
    if (op != kAudioServerPlugInIOOperationReadInput) return noErr;
    if (!main || !cycle) return kAudioHardwareIllegalOperationError;
    float *out = main; memset(out, 0, count * sizeof(float));
    UInt64 last = atomic_load_explicit(&gLastPacket, memory_order_acquire), now = mach_absolute_time();
    if (!atomic_load_explicit(&gEnabled, memory_order_acquire) || !atomic_load(&gStreamActive) || !last || now < last ||
        (double)(now - last) > gTicksPerFrame * KB_AUDIO_SAMPLE_RATE / 4) return noErr;
    double time = cycle->mInputTime.mSampleTime;
    if (!isfinite(time) || time < 0 || time > (double)(UINT64_MAX - count - 1)) return noErr;
    UInt64 epoch = atomic_load_explicit(&gEpoch, memory_order_acquire), first = (UInt64)time;
    for (UInt32 i = 0; i < count; ++i) {
        UInt64 tag = first + i + 1; RingSlot *slot = &gRing[(first + i) % kRingFrames];
        if (atomic_load_explicit(&slot->frame, memory_order_acquire) != tag || atomic_load(&slot->epoch) != epoch) continue;
        UInt32 bits = atomic_load(&slot->bits);
        if (atomic_load_explicit(&slot->frame, memory_order_acquire) == tag) memcpy(&out[i], &bits, sizeof(bits));
    }
    if (atomic_load_explicit(&gEpoch, memory_order_acquire) != epoch || !atomic_load(&gEnabled)) memset(out, 0, count * sizeof(float));
    return noErr;
}
static AudioServerPlugInDriverInterface gInterface = {
    NULL, query, addRef, releaseRef, initialize, createDevice, destroyDevice, addClient, removeClient,
    configuration, configuration, hasProperty, isSettable, getSize, getProperty, setProperty,
    startIO, stopIO, zeroTime, willIO, boundaryIO, doIO, boundaryIO
};
static AudioServerPlugInDriverInterface *gInterfacePointer = &gInterface;
__attribute__((visibility("default"))) void *KeyBridgeAudioFactory(CFAllocatorRef allocator, CFUUIDRef type) {
    (void)allocator;
    if (!CFEqual(type, kAudioServerPlugInTypeUUID)) return NULL;
    gDriver = &gInterfacePointer; atomic_fetch_add(&gRefs, 1); return gDriver;
}
