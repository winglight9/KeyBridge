#!/usr/bin/env bash
KEYBRIDGE_SWIFT_FLAGS=()
python3 "$KEYBRIDGE_ROOT/script/prepare_toolchain.py" "$KEYBRIDGE_ROOT"
if [[ -f "$KEYBRIDGE_ROOT/work/toolchain/use-manifest-overlay" ]]; then
  export SWIFTPM_CUSTOM_LIBS_DIR="$KEYBRIDGE_ROOT/work/toolchain"
fi
if [[ -f "$KEYBRIDGE_ROOT/work/toolchain/overlay.json" ]]; then
  KEYBRIDGE_SWIFT_FLAGS=(-Xswiftc -vfsoverlay -Xswiftc "$KEYBRIDGE_ROOT/work/toolchain/overlay.json")
fi
