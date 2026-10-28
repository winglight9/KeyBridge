# Security and privacy

KeyBridge captures input only while an authenticated, explicitly selected route is active.
Pairing requires comparing the code and approving both Macs. Peer identities are pinned;
traffic uses directional ChaChaPoly keys and strict sequence checks. Raw gesture packets
are bounded and validated before injection. This is a beta implementation, not an
independent security audit.

The development release is locally signed and is not Apple-notarized. Some input-source
identification and native gesture behavior depend on undocumented macOS behavior. Review
compatibility and release notes before updating macOS. FileVault/pre-login input, Touch ID,
and operation inside protected system contexts are not supported.

Device identity seeds remain in the current user's Application Support directory with
owner-only permissions. No keyboard text, raw gesture payloads, SSH passwords, or deployment
credentials are written to application diagnostics. Diagnostics can contain device network
names and local network status; review them before posting publicly.

A link stall, sleep, stop command, or capture error restores local input and releases remote
pressed keys/buttons. Unknown physical input sources remain local. Display-connected mice
are not intentionally forwarded. If a macOS release cannot identify the physical sender,
input fails closed instead of treating all pointers as the trackpad.

Please avoid posting security-sensitive details in public issues. Contact the maintainer
through the GitHub profile to arrange private reporting.
