## Digitus Print v1.0 - Windows-assisted Canon printing

Print using Windows PC sends a selected PDF from Android to the Windows
computer that already successfully prints through the DIGITUS DA-70251.
It reuses the real Windows Canon driver and DIGITUS USB Server.
A companion Windows bridge ZIP, Python 3.10+ and SumatraPDF are required.

Open Print, select a PDF, enter Windows PC IP (not the DIGITUS hub IP),
port 8765 and the pairing token, check the Windows bridge, and send.
Windows must stay on and connected to the printer. Submitted means
accepted by the Windows print spooler, not physical paper verified.
Job idempotency and review gates prevent inadvertent automatic retries.
Local HTTP is unencrypted; use a trusted private LAN only.

Setup: [Windows printing guide](docs/WINDOWS_PRINT_MODE.md).
Direct Android to DIGITUS native NU printing remains unavailable.
The Windows companion archive is distributed separately with this build.

# DigitusPrint — Canon G2420 / DIGITUS DA-70251

Flutter Material 3 application for **Canon PIXMA G2420** over a **DIGITUS DA-70251** network USB hub. The user-selected printer remains G2420 regardless of the name reported by the USB hub.



## NU v0.9.6 — evidence-based driver analysis (still offline)

The supplied 2011 x64 NUServer driver has now been statically
disassembled. Legacy bulk OUT forwards **upper-layer USB client bytes**,
split at **1024 bytes** with a **32-byte NU header**. This indicates that
Windows's opaque 383-byte message is not synthesized by the transport
layer; it is probably generated upstream, but its Canon semantics
remain unknown. Native printing is **still disabled** and NO_RETRY.

New files: [IDA function labeling script](tools/reverse/nu_ida_analysis.py),
[independent PE verifier](tools/reverse/nu_pe_static_map.py),
[findings with confirmed RVAs](docs/NU_IDA_DRIVER_ANALYSIS.md),
and a tested [legacy fragmentation model](lib/services/nu_legacy_fragmenter.dart).
The PE verifier was run on the original driver; the IDA script has not
been executed in IDA because that environment is unavailable here.

## Current status: NU v0.9.5 offline compatibility audit

The 2026-11-14 Windows capture revealed a critical semantic mismatch:
the first 383-byte print-session write is an opaque high-entropy USB
transaction, **not** the first 383 bytes of a Canon IVEC document.
The Android v0.9.4 handshake had matching NU replies but received 0
printer-data bytes where Windows received 487 bytes at sequence 44.

**Native printing is not yet supported.** The former live experimental
print button now performs an **offline, read-only IVEC/NU compatibility
audit** (0 NU/USB bytes transmitted). It does not require a hub
connection or try to print. It retains a copyable diagnostic report.
Older v0.9.3/v0.9.4 behavior below is historical, not current.

See [capture-based root-cause investigation](docs/NU_G2010_SETUP_MISMATCH.md).

## Capture-verified NU handshake probe — v0.9.4 (2026-11-14)

The v0.9.3 print test stalled after its first 383-byte OUT:
its 02/04 reads targeted logical pipe `0x82`, but the original
Windows NU capture requires logical pipe `0x81`, with header tail
`00 12 82 24`. Windows also sends a 16-byte OUT at seq45, not
the 1024-byte write the app tried.

v0.9.4 now matches the first five captured client headers (seq40–44)
and stops before the next proprietary messages. The button is labeled
**Run NU handshake probe (not full printing)**, preserves opt-in
consent and no-retry semantics, and exports full TX/RX metadata.
**It does not print a full page.** The remaining vendor communication
and G2010/G2020 raster compatibility must be decoded and verified.
The older experimental full-job v0.9.3 description below is retained
only as historical context.

## Current native NU experiment — v0.9.3 (2026-11-14)

The Print > Test 1-page NU printing button uses proprietary NU TCP/4660
rather than LPR. The current app constructs 1460-byte client records,
matches out-of-order 02/03, 02/05 and 02/09 replies using 16-bit sequence
numbers, sends the initial prep/383-byte OUT/three bulk IN read pipeline,
and interleaves further 1024-byte bulk transfers. A full TX/RX diagnostic
trace can be copied after a print attempt.

Physical printing is NOT verified. The connected Canon G2010 ID
(VID 04A9 / PID 183A) differs from the G2020-family IVEC raster
profile, and the precise bulk IN flags and printer status semantics are
still unverified. Never automatically retry or resume uncertain output.

Older LPR notes below are historical, not the current native sender.

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

## v0.7.1 compatibility diagnostics for the LPR queue ACK / control-header disconnect

A real phone test with `192.168.0.74` and queue `a9043a1802` received `queue: ACK 0` then the hub closed the connection before `control header` acknowledgement. This proves only that the initial queue transaction was acknowledged, **not** that the control file, raster bytes, or page were accepted.

RFC 1179 allows control and data file transfer in either order and some nonconforming older LPR servers require the data file first. The test print now offers an explicit **Compatibility: send raster data first** switch; the default remains control-first. This is **manual**, never an automatic retry, to avoid duplicate prints. Logs also include the ephemeral local TCP source port, useful for testing the RFC 1179 privileged source-port restriction hypothesis (Android apps cannot bind privileged TCP ports without elevated permissions). The hub's actual rules and Canon G2420 raster compatibility remain unverified.

If data-first also closes after queue ACK, test from Windows with the same queue and a confirmed correct Canon Windows printer driver, or capture that LPR traffic before implementing further transport guesses. Physical output must be independently confirmed.

## v0.7.2 legacy LPR source-port diagnostics

RFC 1179 specifies the client-side source TCP port range 721–731, while Android's ordinary app sandbox usually chooses an ephemeral local port. Some old LPD servers enforce this, but the queue ACK/control-header disconnect does **not** prove it is the cause. Microsoft's Standard TCP/IP Port Monitor can use ephemeral source ports in LPR mode, so old hubs vary. A manual, opt-in “RFC1179 reserved source port” switch now binds local port 721–731 before opening the connection. No root escalation, no automatic fallback, and no retry; a failed bind produces a clear message *before sending any print data*. Use the existing Data First switch separately, only for a deliberate one-page test. The Canon G2420 print profile remains unverified.

## v0.8 updater / safe raw-port diagnostics

- The Discover screen has an **App updates** panel; it checks GitHub Releases and compares semantic versions, downloads a signed APK from the project's release page, verifies its GitHub-provided SHA-256 digest, then opens the Android installer on explicit user action. It does not bypass user confirmation.
- GitHub Actions can publish an update APK to the public release feed when *all four* stable signing secrets are present: `ANDROID_RELEASE_KEYSTORE_B64`, `ANDROID_RELEASE_KEYSTORE_PASSWORD`, `ANDROID_RELEASE_KEY_ALIAS`, and `ANDROID_RELEASE_KEY_PASSWORD`. Never commit the keystore or signing passwords.
- **Important migration:** previous CI debug APKs use ephemeral signing certificates. Android cannot update those in place with a differently signed release APK. Make a backup and uninstall the old prototype once before installing the first properly signed release; later updates work in place as long as the release key never changes.
- New installations must enable **Install unknown apps** for DigitusPrint through Android settings. Updates prompt for explicit Android approval.
- TCP `9100` was added to the default read-only network port checks. An open port does not prove that the DA-70251 forwards printer data. The app intentionally **does not** blast raster data to an unverified raw socket.
- The existing **Data First** switch remains a manual, single-job diagnostic. Neither this change nor the updater tests the printer physically.

## v0.8.1 vendor USB-over-IP research track

DigitusPrint now also includes a passive native-Dart probe for the Windows NU V1.25 **TCP 4660** service, plus a unit-tested `UNT$` fingerprint recognizer based on the real uploaded packet capture. The probe connects briefly and listens without sending *any* client handshake or USB commands. It can report TCP reachability or a spontaneous server greeting, but **it cannot claim a USB port or print**. Those operations require confirmed vendor opcodes and framing from a capture starting *before* Windows utility Search/Connect/Disconnect. The app continues to support the separate LPR track. No Windows installer or binary is bundled.

## Confirmed physical hub model

The owner confirmed the physical device is **DIGITUS DA-70251**, not DA-70254. Its official manual primarily documents the USB Server utility's virtual USB connections and per-port connection control. LPR probing remains an experimental compatibility track only; LPR instructions specific to DA-70254 do not prove DA-70251 support. Vendor TCP 4660 remains partially identified from the user's own network trace, but no verified device-claim/USB bulk protocol exists yet.
