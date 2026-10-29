# KeyBridge Microphone (experimental)

An original MIT AudioServerPlugIn for macOS 14 or newer on Apple Silicon.
One virtual **input** stream: 48 kHz, mono, Float32. No physical microphone is
opened by the driver, and it never changes the system's default input.

Build (no installation and no audio-service restart):

```sh
script/build_audio_driver.sh
```

Output: `outputs/audio-driver/KeyBridge-Microphone.pkg`. Bundle this file in
`KeyBridge.app/Contents/Resources/KeyBridge-Microphone.pkg` **before** signing the
app. The package installs only `KeyBridgeMicrophone.driver` to
`/Library/Audio/Plug-Ins/HAL`; it has no postinstall script.

To let the user explicitly install the component:

```sh
script/install_audio_driver.sh
```

Apple's Installer displays administrator authorization. The helper intentionally
does not restart coreaudiod: if the device does not appear, restart the Mac when
convenient. Choose KeyBridge Microphone inside the recording/call application.
The receiving app's microphone privacy permission still applies.

`KEYBRIDGE_AUDIO_SIGN_IDENTITY` optionally selects a driver signing identity.
The default is an ad-hoc signature for experimental local distribution. No
DriverKit entitlement or app capture entitlement is attached to the HAL bundle.
Developer ID distribution/notarization is separate work; a successful build alone
does not establish successful loading under every Mac's security policy.

`IPC.md` documents the Swift writer and the security boundary. The optional
`KBAudioWriter.c` convenience library is built too, but the app can use CoreAudio
directly. The driver authenticates BEGIN, then checks PID/start time for PUSH;
its realtime ReadInput callback uses only lock-free atomics, memory copies, and
mach time. Silence is returned before data, after END, for missing slots, and
when 250 ms elapses since the last accepted packet.

No runtime, driver-loading, enumeration, or acoustic test has been performed by
the build script. Do those explicitly on the target Mac before claiming support.
