# KeyBridge / 键桥 1.6

1.6 adds automatic-lock prevention and fixes issues found during long-running wired use.

## Changes

- The menu popover closes when focus leaves KeyBridge or the user clicks another app.
- Long idle periods no longer make the main heartbeat confuse an App Nap/scheduling delay with a dead peer.
- A brief heartbeat gap now returns input locally while retaining the selected route. The next successful heartbeat restores the same route automatically, and a single missed heartbeat no longer tears down microphone sharing.
- Locking or leaving the user session no longer stops microphone sharing by itself. Display/session suspension is announced to the other Mac so the virtual microphone session stays open without triggering a false audio-timeout failure. A real system sleep closes the link and schedules one reconnect after wake.
- Two-finger scrolling now forwards the complete native continuous-scroll event, including phase, momentum and the source Mac's natural-scroll direction marker. This removes the reconstructed-event direction mismatch.
- Empty stale connection details are cleared after a successful reconnect.
- Added an optional **Prevent automatic lock** switch. While KeyBridge is connected, it holds a macOS display-sleep assertion so an idle MacBook does not lock before its next keyboard or trackpad input. Turning it off or quitting KeyBridge releases the assertion immediately. Manual lock, lid close and system sleep remain under macOS control.

## Update both Macs

The preserved native-scroll path and the new microphone pause/resume messages require 1.6 on both Macs. A 1.6 Mac talking to an older peer keeps the previous reconstructed scroll path for compatibility; microphone sharing uses the matched 1.6 protocol.

Bluetooth remains useful as a temporary or backup link; its latency is higher than the direct Thunderbolt path. For wired operation, use a dual USB-C cable explicitly rated for Thunderbolt 3/4/5 (or an equivalent Thunderbolt-compatible USB4 cable) and use a rear Thunderbolt port on a Mac mini.
