#!/usr/bin/env bash
set -euo pipefail
KEYBRIDGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KEYBRIDGE_ROOT"
source "$KEYBRIDGE_ROOT/script/toolchain_env.sh"
swift run "${KEYBRIDGE_SWIFT_FLAGS[@]}" KeyBridgeChecks "$@"
