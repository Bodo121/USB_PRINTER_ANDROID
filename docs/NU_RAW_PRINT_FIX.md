# NU bulk RAW print framing: correction from the Windows capture

On 2026-11-14 an Android IVEC test timed out during bulk OUT.
Re-examining the *actual packets* in `plm222.pcapng` revealed a
byte-for-byte mismatch between Android's outbound packet and Windows.

One Windows bulk OUT request to endpoint 0x01 (sequence 0x29)
has a **48-byte frame header** (16-byte descending prefix plus
32-byte UNT header), not 56 bytes:

```text
10 0f 0e 0d 0c 0b 0a 09 08 07 06 05 04 03 02 01
55 4e 54 24 01 7f 02 02 29 00 00 00 00 00 01 00
01 00 30 f0 7f 01 00 00 00 00 80 29 00 12 72 20
```

The length 0x017f is big-endian at offsets 20–21 and repeated
little-endian at 36–37. The endpoint is offset 32. The **raw
USB bulk data starts at byte 48**, not 56. Windows pads this
particular request to 1460 bytes. A matching 32-byte 02/03
completion uses the same sequence at bytes 8 and 27 and
repeats the transfer length at bytes 20–21 in little-endian.

The old Android implementation incorrectly used
`[count>>8,count&255,02,02,seq, ... 01 00 01 00 30 f0 ...]`
and started the payload at offset 56. This produced an invalid
header and a plausible reason for the timeout.

The replacement code builds the **actual captured header**, copies
Canon IVEC raster bytes directly into the NU payload, validates
sequence/length on completion, and never retries uncertain output.
The max chunk remains 383 bytes because the capture does **not**
prove that larger writes work.

This is a plausible experimental print transport, **not a verified
full driver**. Opaque transport fields 00 12 72 20 and acceptance
semantics may depend on session state. Windows printer-class ID
reported `CMD:BJRaster3,IVEC`; the bundled G2020-family IVEC raster
encoder remains experimental for the USB G2010-series descriptor.
A successful physical page is still required before we claim
reliable printing. **Do not retry after a timeout without checking
printer state.**
