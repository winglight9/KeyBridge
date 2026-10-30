#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build and package only. This script never installs or restarts the audio server.
set -euo pipefail
KEYBRIDGE_AUDIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYBRIDGE_AUDIO_OUT="${KEYBRIDGE_AUDIO_OUT:-$KEYBRIDGE_AUDIO_ROOT/outputs/audio-driver}"
KEYBRIDGE_AUDIO_STAGE="$KEYBRIDGE_AUDIO_OUT/package-root"
KEYBRIDGE_AUDIO_BUNDLE="$KEYBRIDGE_AUDIO_STAGE/Library/Audio/Plug-Ins/HAL/KeyBridgeMicrophone.driver"
KEYBRIDGE_AUDIO_SDK="$(xcrun --sdk macosx --show-sdk-path)"
# Clean only this script's private payload staging area.
rm -rf "$KEYBRIDGE_AUDIO_STAGE"
mkdir -p "$KEYBRIDGE_AUDIO_BUNDLE/Contents/MacOS" "$KEYBRIDGE_AUDIO_BUNDLE/Contents/Resources"
cp "$KEYBRIDGE_AUDIO_ROOT/AudioDriver/Resources/Info.plist" "$KEYBRIDGE_AUDIO_BUNDLE/Contents/Info.plist"
cp -R "$KEYBRIDGE_AUDIO_ROOT/AudioDriver/Resources/en.lproj" "$KEYBRIDGE_AUDIO_ROOT/AudioDriver/Resources/zh-Hans.lproj" "$KEYBRIDGE_AUDIO_BUNDLE/Contents/Resources/"
xcrun --sdk macosx clang -std=c11 -arch arm64 -mmacosx-version-min=14.0 -isysroot "$KEYBRIDGE_AUDIO_SDK" \
  -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations -fvisibility=hidden -bundle \
  "$KEYBRIDGE_AUDIO_ROOT/AudioDriver/KeyBridgeMicrophone.c" \
  -framework CoreAudio -framework CoreFoundation -framework Security -framework SystemConfiguration \
  -o "$KEYBRIDGE_AUDIO_BUNDLE/Contents/MacOS/KeyBridgeMicrophone"
xcrun --sdk macosx clang -std=c11 -arch arm64 -mmacosx-version-min=14.0 -isysroot "$KEYBRIDGE_AUDIO_SDK" \
  -O2 -Wall -Wextra -Werror -c "$KEYBRIDGE_AUDIO_ROOT/AudioDriver/KBAudioWriter.c" -o "$KEYBRIDGE_AUDIO_OUT/KBAudioWriter.o"
xcrun ar rcs "$KEYBRIDGE_AUDIO_OUT/libKeyBridgeAudioWriter.a" "$KEYBRIDGE_AUDIO_OUT/KBAudioWriter.o"
# A HAL plug-in is not the capture app: do not attach the app's audio-input entitlement.
# Ad-hoc signing is for local experimental builds; release identity can be supplied explicitly.
codesign --force --sign "${KEYBRIDGE_AUDIO_SIGN_IDENTITY:--}" --timestamp=none "$KEYBRIDGE_AUDIO_BUNDLE"
/usr/bin/pkgbuild --root "$KEYBRIDGE_AUDIO_STAGE" --install-location / --ownership recommended \
  --identifier org.keybridge.audio.microphone.pkg --version 1.3 "$KEYBRIDGE_AUDIO_OUT/KeyBridge-Microphone.pkg"
printf '%s\n' "$KEYBRIDGE_AUDIO_OUT/KeyBridge-Microphone.pkg"
