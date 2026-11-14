# DigitusPrint v0.5 — Android native hub discovery and Canon test printing

Flutter Material 3 application for **Canon PIXMA G2420** over a **DIGITUS DA-70254** network USB hub. The user-selected printer remains G2420 regardless of the name reported by the USB hub.

## Hub discovery and first-run experience

- Start with the last known hub, or `192.168.0.74` if there is no saved connection (editable).
- Identify a known old firmware HTTP status page via read-only GET requests and show firmware and USB connection information. No passwords or hub configuration changes.
- If there is no response from the known host, scan private local IPv4 /24 candidates for port 515. Discovery is cancellable (in-progress network requests may still finish, but results are ignored).
- Probe a short list of likely LPR queues via read-only RFC1179 status requests. Save a queue automatically **only if exactly one positive candidate** is returned. These are heuristics: **LPR has no standardized queue enumeration** and the hub's status page does not provide the actual queue identifier. A supported queue must not be inferred from a TCP open port alone. Manual settings remain available under Advanced.
- Display the configured Canon model, separately from the USB server's own device-name field.

## Experimental print path

The native Kotlin IVEC/PWG Raster pipeline is adapted from GPL-3.0-or-later-licensed [noble6/canon-universal-driver](https://github.com/noble6/canon-universal-driver); see `LICENSE` and `native/`. It uses a related G2020 profile as an *experimental, unverified candidate* for G2420. Documents (PDF, PNG, JPG, TXT) are prepared as PDF in Flutter and the first page is rendered natively with Android PdfRenderer in bands before IVEC/PWG encoding and binary LPR transfer.

**Do not claim printing works until a real G2420 test page prints.** An LPR acknowledgement proves only that the hub accepted the bytes. The app doesn't read true Canon ink levels or physical print-completion status. Maintenance, scanning, and multipage direct printing are not yet available. The Android system print dialog still requires an installed compatible PrintService.

## Performance and UI

- Saved-hub fast path avoids entire-network scanning on most launches.
- Scan network probes are concurrent; preview rendering is opt-in; progress and cancellation are supported.
- Native Android high-refresh display-mode preference requests the best mode at native resolution (where possible), but does not force 120 FPS.

## Build

GitHub Actions runs `flutter pub upgrade --major-versions`, `flutter analyze --no-fatal-infos lib`, `flutter test`, and `flutter build apk --debug`. The APK is attached to each successful Actions run as `DigitusPrint-Flutter-debug`. Build is Android-native, with no Windows runtime dependency.

## Source license

GPL-3.0-or-later; the Canon IVEC/PWG driver portions are adapted from the named upstream GPL project.

## Native USB-over-IP protocol research (v0.6)

A separate read-only standard USB/IP (TCP 3240) DEVLIST diagnostic has been added. This is a **protocol compatibility check only**: the legacy NU V1.25 software is not known to use Linux USB/IP. A failed check does not mean your hub is unreachable or disconnected. **Direct vendor USB-over-IP attachment and printing are not yet implemented.** Use `tools/analyze_nu_capture.py` to inspect a Windows Wireshark capture and `docs/NU_V125_PROTOCOL.md` for the exact capture workflow. No proprietary Windows binary is bundled in Android.

### NU V1.25 original installer research

The supplied 146 MiB NU_V1.25 software CD has now been inspected, with an embedded CAB extracted to reveal nested InstallShield installers for XP/Vista/Windows 7 and release notes referencing E1868/E2868/E3868. The 2011 release notes explicitly mention fixes to incorrect Printer/MFP queue names. Protocol decoding remains incomplete. See [NU V1.25 protocol research](docs/NU_V125_PROTOCOL.md). Proprietary Windows binaries are not bundled in this Android project.

## v0.7 USB and print diagnostics

- The Canon G2420 one-page test now reports each **RFC1179 LPR acknowledgement**: queue selection, control-file header, control-file upload, data-file header and raster upload. It also reports the encoded job byte count and identifies the failed stage when an ACK is rejected, the connection closes, or times out. All-zero ACKs mean *hub/LPD transport accepted the job*, NOT that paper was printed.
- An **empty LPR queue-status response** is explicitly *not* treated as an accepted job. The user-supplied queue `a9043a1802` is the fallback value only if the user has no saved queue; an existing saved value is preserved.
- Multi-port *network service* diagnostics check TCP ports `4660,3240,515` by default (editable up to 16). TCP 4660 is grounded in the user's NU V1.25 packet capture and `UNT$` marker; opening a TCP connection only verifies socket reachability, **not a functional proprietary USB-over-IP session**.
- The hub has **four physical USB sockets**, selectable in diagnostics (1–4) and saved for future protocol development. This selection DOES NOT yet route USB traffic or select an LPR queue. These are different from network TCP port numbers.
- The proprietary NU V1.25 attach, device list and USB bulk/control framing are still unknown; no unsafe or made-up vendor commands are sent. The Canon G2020-family raster profile remains *unverified for the G2420*.

See [NU V1.25 protocol notes](docs/NU_V125_PROTOCOL.md) for extraction and capture findings.
