# Experimental native NU print path

This branch removes the LPR **print sender** and switches the one-page
test to native NU TCP 4660. The Android Kotlin layer only renders page 1
to Canon G2020-family IVEC raster bytes and returns them through the
`digitus_print/canon` method channel (`prepareRaster`). Dart owns the
live NU session, Canon IEEE 1284 verification, experimental USB bulk OUT
transfer and response checks.

User workflow:
1. Discover > Connect and verify Canon USB.
2. Read Canon printer-class ID, requiring `CMD:...IVEC`.
3. Print > Prepare one-page printer test.
4. Explicitly enable experimental NU printing and acknowledge risk.
5. Tap Test 1-page NU printing. Never auto-retry uncertain delivery.

**WARNING**: The bulk-OUT dynamic packet header, payload offset,
sequence reuse and completion status are still reverse-engineering
hypotheses. The only known printer OUT capture has four 02/02 requests,
not a complete known-successful print. The code intentionally checks
matching 02/03 replies and aborts on any mismatch, but such matching
does not prove a successful USB transfer or physical printing.

The source retains older LPR discovery diagnostics for compatibility,
but the Canon print button no longer sends to TCP 515. The old LPR
sender has been removed from the native Kotlin printer implementation.
The experimental sender does not support resume or automatic retry.
A complete successful Windows test-page PCAP remains important to
verify the final NU framing and transfer-completion semantics.

## v0.9.3 trace export

The Print tab includes Copy full NU TX/RX debug log after an attempt.
It includes message type, full 16-bit sequence, size, and the first 48
raw bytes for each TX and RX record. RX data may expose 16 bytes of
printer status content; review before sharing. No automatic retry or
resumption is attempted. A matching transport reply does not prove a
page printed. The G2020-family raster profile is not yet proven for the
reported G2010 series device.

## v0.9.4: capture-matched diagnostic, deliberately no full print

The previous v0.9.3 sent IN requests on `0x82` rather than the
Windows client's logical NU pipe `0x81`; it also sent 1024 bytes
at seq45 where Windows sent only 16. The old sender is not a validated
printing implementation.

The new user-facing button runs a limited, opt-in handshake probe:
preparation seq40; 383-byte write seq41; three 1024-byte reads seq42–44
using the Windows header `00 12 82 24`. If all reads are empty, stop
and record the entire TX/RX header trace. If any read contains data,
report a successful *probe*, but do not send seq45 or a complete print
job. Printer output and IVEC model compatibility remain unverified.

## v0.9.5: disable unsafe synthetic USB setup writes

The original Windows trace has an opaque 383-byte payload at seq41,
while the Android sender substituted the first 383 bytes of the
Kotlin-generated G2020 IVEC print stream. These payloads have different
structures. The empty seq44 response in v0.9.4 is consistent with an
uncompleted printer setup, but does not prove exactly what the device
rejected. The native test is now an **offline compatibility audit**:
zero NU/USB print traffic, zero automatic retries and no claim of
printed output. See [detailed capture comparison](NU_G2010_SETUP_MISMATCH.md).
