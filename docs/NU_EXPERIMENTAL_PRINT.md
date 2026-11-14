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
