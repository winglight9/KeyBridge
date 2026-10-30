#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Explicit installation helper; does not kill or restart coreaudiod.
set -euo pipefail
KEYBRIDGE_AUDIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYBRIDGE_AUDIO_PKG="${1:-$KEYBRIDGE_AUDIO_ROOT/outputs/audio-driver/KeyBridge-Microphone.pkg}"
if [[ ! -f "$KEYBRIDGE_AUDIO_PKG" ]]; then
  printf '%s\n' "Audio component package not found. Run script/build_audio_driver.sh first." >&2
  exit 1
fi
if [[ "$(id -u)" == 0 ]]; then
  /usr/sbin/installer -pkg "$KEYBRIDGE_AUDIO_PKG" -target /
else
  # Apple's Installer displays the component and asks for administrator authorization.
  /usr/bin/open -W "$KEYBRIDGE_AUDIO_PKG"
fi
printf '%s\n' 'The component does not change the default microphone. The installer reloads only KeyBridge’s virtual microphone; no computer restart is requested.'
