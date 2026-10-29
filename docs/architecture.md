# Architecture

## Modules

`KeyBridgeCore` contains protocol values, framing, secure-session state, compact input coding, bounded native gesture serialization, wired-state classification and legacy HID report interpretation. `KeyBridge` owns the SwiftUI popover, AppKit status item, platform transports, physical-device event capture, system network snapshots and Quartz injection. `BridgeStore` serializes session and route changes on the main queue. Capture and its lease watchdog run independently of the UI thread.

## Identity and authenticated channels

Every installation generates a Curve25519 signing key. Its raw 32-byte seed is atomically stored in an owner-only Application Support directory with file mode 0600. A symlink, wrong owner, broad permissions or wrong length is rejected. Existing identity is not silently regenerated on read failure. The stable public-key fingerprint supplies the installation ID; the current macOS local hostname supplies its display label.

A signed hello binds protocol version, identity metadata, ephemeral X25519 key and random nonce. Peers derive a common verification code and independent directional ChaChaPoly keys with HKDF-SHA256. Unknown or changed peers require approval on both Macs; pinned identities can reconnect without a fresh approval. Strict sequence numbers reject replay and sequence gaps. Input is accepted only after mutual approval.

TCP and BLE share bounded four-byte length framing. Ordinary keyboard/motion/button/scroll packets use compact input coding. Native gesture packets use a bounded data payload inside the authenticated session. BLE writes and notifications fragment to negotiated sizes and use flow control. Queue overflow closes the link rather than creating an unbounded input backlog. Frames and queues have hard size limits. The app does not log keystrokes or raw gestures.

## Route transaction

Both popovers edit one route: source installation ID, target installation ID and a fresh UUID token. A route change stops old capture and releases injected keys/buttons first. The destination checks Accessibility permission and sends `routeReady`; the source installs filtering taps and sends `routeActive`. Input carries the route token. The receiver checks token, source identity, destination identity and active state before injection.

Selecting the source as its own destination stops remote forwarding. Retry reconnects only the saved device and leaves forwarding explicit. Transport changes require confirmation and pause forwarding. A new installation defaults to wired; a saved manual choice is retained. There is no automatic transport failover or Wi-Fi fallback.

## Transports and wired diagnostics

Bluetooth uses Core Bluetooth LE discovery and duplex GATT writes/notifications, bounded flow-control queues and a low connection-latency request. Device network names become available during the authenticated hello and can be cached for discovery labels. The application verification code remains separate from any system Bluetooth pairing.

The wired path binds Bonjour/TCP to the configured Thunderbolt Bridge. `WiredSystemSnapshot` reads SystemConfiguration preferences, dynamic link state and interface addresses without modifying configuration. `WiredDiagnosis` classifies missing/unreadable configuration, disabled bridge, link down/unknown, waiting for address and ready states. Transport-level messages distinguish no discovered peer, unavailable interface and denied network access. A periodic read also observes changes when the default network path is unchanged. A scoped IPv6 UDP probe resolves the bridge interface even when the default network path lists Wi-Fi; the probe sends no application data. TCP disables delay for small input packets. Heartbeats run in common run-loop modes so an open menu does not stall them.

A missing link is not a cable-capability test: an unplugged, unsuitable or faulty cable, a port issue and an unavailable peer are not distinguishable from that one observation. Messages preserve the distinction between evidence and possible causes.

## Physical input isolation

The ordinary source path uses a Quartz HID event tap. Runtime-resolved `CGEventCopyIOHIDEvent` obtains the physical HID event; `IOHIDEventGetSenderID` identifies its IORegistry sender. These accessors are undocumented, so availability and behavior are compatibility dependencies. Allowlisted internal keyboard/trackpad service IDs and their descendants identify eligible input. Unknown and excluded senders pass locally. Failure to obtain the required identification interface prevents broad capture rather than forwarding every pointer.

Recognized internal trackpad movement restores the source cursor to its local anchor after capture. External/unidentified pointer events pass locally and update the anchor. This avoids global cursor association/disassociation and global delta compensation, which can affect an external mouse.

The original exclusive IOHID capture attempt failed on the development M1 with `kIOReturnNotPrivileged` despite permissions. It is no longer the live capture path. The legacy SPI parser remains in the core with parser checks; those checks do not exercise current live capture.

## Experimental native gesture path

The source-side `native-gestures` preference defaults to false. Changing it stops forwarding. Capture enables the path only when the peer advertises the compatible native-gesture version. A dedicated session gesture tap handles Quartz event types 29 and 30 separately from ordinary HID motion/key capture. Native-gesture protocol version 2 carries both types. It requires recognized built-in trackpad sender IDs; a system-origin type-30 companion without its own sender is admitted only within 100 ms of a recognized internal gesture. Other unknown/synthetic sources remain local.

The implementation serializes the original native gesture event with a 16 KiB limit and validates the decoded Quartz type before injection. It preserves gesture fields rather than mapping finger motions to application commands or keyboard shortcuts. Replay resets machine-local source, target cursor position and timestamp, and adds a replay marker to prevent recapture. Stopping a route can send a cancellation phase for an ongoing gesture, not a substitute application action.

Types 29/30 and their phase behavior rely on undocumented Quartz details. Unit/protocol checks cannot demonstrate that macOS or an app will recognize every replayed gesture. The user confirmed multi-finger behavior in the wired setup recorded below; other Mac/OS/app combinations and exhaustive individual gestures still need physical acceptance testing. A working synthetic/remote event is not evidence of physical sender matching or native system-gesture recognition.

## Failure recovery and validation boundaries

The UI heartbeat marks the link unstable after 650 ms, stops forwarding and releases receiver state. The independent capture watchdog revokes its lease after 1 s even if the UI queue stalls. A 1.2 s session timeout closes the channel. Sleep, termination, tap errors and route errors also stop interception. Both Input Monitoring and Accessibility are required on the source; the receiver needs Accessibility.

`script/test.sh` runs a standalone Swift check executable. Checks cover pairing/authentication/framing, input bounds, legacy parser behavior, native-gesture serialization/validation and wired classifier fixtures. Passing checks establish those code paths only; they do not prove physical cable compatibility, actual sender matching, end-to-end latency or target recognition of system gestures.

The user has verified Bluetooth typing, pointer movement, clicks, dragging and two-finger scrolling on an M1 Pro MacBook/M4 Mac mini setup, with noticeable Bluetooth latency. On 2026-10-29 the user also confirmed wired input, multi-finger gestures, source trackpad isolation and external-mouse behavior on that pair, both running macOS 15.8.1. These results do not establish universal cable, hardware, gesture or OS compatibility. Public release notes should record observed results without converting implementation or compilation into a hardware-support claim.
