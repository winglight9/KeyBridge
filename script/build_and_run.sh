#!/usr/bin/env bash
set -euo pipefail
KEYBRIDGE_MODE="${1:-run}"
KEYBRIDGE_CONFIGURATION="${KEYBRIDGE_CONFIGURATION:-debug}"
KEYBRIDGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KEYBRIDGE_ROOT"
source "$KEYBRIDGE_ROOT/script/toolchain_env.sh"
KEYBRIDGE_APP="$KEYBRIDGE_ROOT/outputs/KeyBridge.app"
if [[ "$KEYBRIDGE_MODE" != "--build-only" ]]; then
  pkill -x KeyBridge >/dev/null 2>&1 || true
fi
swift build "${KEYBRIDGE_SWIFT_FLAGS[@]}" -c "$KEYBRIDGE_CONFIGURATION" --product KeyBridge
KEYBRIDGE_BINARY="$(swift build "${KEYBRIDGE_SWIFT_FLAGS[@]}" -c "$KEYBRIDGE_CONFIGURATION" --show-bin-path)/KeyBridge"
mkdir -p "$KEYBRIDGE_APP/Contents/MacOS" "$KEYBRIDGE_APP/Contents/Resources/en.lproj" "$KEYBRIDGE_APP/Contents/Resources/zh-Hans.lproj"
cp "$KEYBRIDGE_BINARY" "$KEYBRIDGE_APP/Contents/MacOS/KeyBridge"
cp "$KEYBRIDGE_ROOT/Assets/Brand/AppIcon.icns" "$KEYBRIDGE_ROOT/Assets/Brand/MenuBar.pdf" "$KEYBRIDGE_ROOT/Assets/Brand/MenuBarActive.pdf" "$KEYBRIDGE_APP/Contents/Resources/"
# Give LaunchServices a fresh, explicit icon resource identity when replacing older betas.
cp "$KEYBRIDGE_ROOT/Assets/Brand/AppIcon.icns" "$KEYBRIDGE_APP/Contents/Resources/KeyBridgeAppIcon.icns"
cat > "$KEYBRIDGE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>KeyBridge</string>
<key>CFBundleIdentifier</key><string>org.keybridge.app</string>
<key>CFBundleName</key><string>KeyBridge</string>
<key>CFBundleDisplayName</key><string>KeyBridge</string>
<key>CFBundleIconFile</key><string>KeyBridgeAppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.3</string>
<key>CFBundleVersion</key><string>6</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>NSBluetoothAlwaysUsageDescription</key><string>Connect directly to your paired Mac to share its keyboard and trackpad.</string>
<key>NSBluetoothPeripheralUsageDescription</key><string>Connect directly to your paired Mac to share its keyboard and trackpad.</string>
<key>NSLocalNetworkUsageDescription</key><string>Discover and connect to your other Mac over the direct Thunderbolt cable.</string>
<key>NSMicrophoneUsageDescription</key><string>Share this Mac’s microphone with your paired Mac only when you enable microphone sharing.</string>
<key>NSBonjourServices</key><array><string>_keybridge._tcp</string></array>
</dict></plist>
PLIST
cat > "$KEYBRIDGE_APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" <<'STRINGS'
"CFBundleDisplayName" = "键桥";
"NSMicrophoneUsageDescription" = "仅在你开启麦克风共享后，将本机麦克风通过有线连接共享给已配对的 Mac。";
"NSBluetoothAlwaysUsageDescription" = "通过蓝牙直连已配对的 Mac，共享键盘和触摸板。";
"NSBluetoothPeripheralUsageDescription" = "通过蓝牙直连已配对的 Mac，共享键盘和触摸板。";
"NSLocalNetworkUsageDescription" = "通过雷雳直连线发现并连接另一台 Mac。";
STRINGS
# Bundle the optional receiver installer; it is never run by the build or app startup.
"$KEYBRIDGE_ROOT/script/build_audio_driver.sh" >/dev/null
cp "$KEYBRIDGE_ROOT/outputs/audio-driver/KeyBridge-Microphone.pkg" "$KEYBRIDGE_APP/Contents/Resources/KeyBridge-Microphone.pkg"
if [[ -n "${KEYBRIDGE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --sign "$KEYBRIDGE_SIGN_IDENTITY" --options runtime --timestamp=none --entitlements "$KEYBRIDGE_ROOT/Assets/KeyBridge.entitlements" "$KEYBRIDGE_APP"
else
  python3 "$KEYBRIDGE_ROOT/script/prepare_signing.py" "$KEYBRIDGE_ROOT" --sign "$KEYBRIDGE_APP"
fi
case "$KEYBRIDGE_MODE" in
  --build-only) printf '%s\n' "$KEYBRIDGE_APP" ;;
  run) /usr/bin/open -n "$KEYBRIDGE_APP" ;;
  --verify) /usr/bin/open -n "$KEYBRIDGE_APP"; sleep 1; pgrep -x KeyBridge ;;
  --debug) /usr/bin/lldb -- "$KEYBRIDGE_APP/Contents/MacOS/KeyBridge" ;;
  --logs) /usr/bin/open -n "$KEYBRIDGE_APP"; /usr/bin/log stream --info --style compact --predicate 'process == "KeyBridge"' ;;
  --telemetry) /usr/bin/open -n "$KEYBRIDGE_APP"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "org.keybridge.app"' ;;
  *) printf '%s\n' 'Usage: build_and_run.sh [run|--build-only|--verify|--debug|--logs|--telemetry]' >&2; exit 2 ;;
esac
