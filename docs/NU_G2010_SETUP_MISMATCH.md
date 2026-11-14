# Why the v0.9.4 NU handshake returned no printer data

## Grounding

The original owner-provided `plm222.pcapng` contains a complete
Windows USB Server TCP/4660 session against the DIGITUS DA-70251.
This investigation reassembled the session using TCP sequence numbers,
removed retransmissions and read application-level NU messages.
No private binary print payload is included in this repository.

## Evidence from the two Windows setup transactions

| Request | Header | Data characteristics |
| --- | --- | --- |
| seq 40 | 02/08, 64 bytes, logical pipe 01 | endpoint preparation |
| seq 41 | 02/02, 383 bytes, logical pipe 01 | opaque high-entropy bytes, prefix `57 54 b9 ed 21 b2 10 0f` |
| seq 42/43 | 02/04, 1024 bytes, logical pipe 81 | responses contain 0 bytes |
| seq 44 | 02/04, 1024 bytes, logical pipe 81 | response contains 487 bytes, opaque |
| seq 45 | 02/02, 16 bytes, logical pipe 01 | another opaque binary message |
| seq 46/47 | 02/04, 512 bytes, logical pipe 81 | replies 0 and 24 bytes |
| seq 75 | 02/08, 64 bytes, logical pipe 01 | second preparation |
| seq 76 | 02/02, 383 bytes, logical pipe 01 | different opaque bytes, prefix `f1 f2 42 37 e3 19 00 d0` |

The seq41 payload has Shannon entropy of approximately 7.45 bits
per byte and seq76 approximately 7.41 bits per byte. Their first eight
bytes differ, and no byte position among the 383 aligned bytes is
identical. These facts do **not** prove encryption; the binary may
involve compression, encoded printer commands, or a session-dependent
exchange.

For reproducibility without distributing the content:
- seq41 383-byte payload SHA-256:
  `2378d2cb07bdfee5044d0ed2b8323ab2e3beeac7f513e134d92b8d44e0312c10`
- seq76 383-byte payload SHA-256:
  `8f9639bb86000bfd420da2ef734d7b8ca8bf99109ebc58c5bcee1f45df08f43e`

The Android v0.9.4 log shows properly framed NU messages, matching
ACKs for seq41-44, and *zero* returned bytes on all three reads.
Its 383-byte seq41 payload was the beginning of the Kotlin-generated
Canon G2020 IVEC print stream, which starts with an XML declaration
(`<?xml`). That is not the same content as Windows seq41.

**Conclusion:** A valid NU transport header cannot make a print
document interchangeable with an unknown printer setup command.
Changing the endpoint, padding, timeout, or making a larger pipeline
will not generate the missing setup/response logic. Sending arbitrary
IVEC data at seq41 can leave device state and print delivery uncertain.

## v0.9.5 fail-closed behavior

The UI offers a **read-only, offline compatibility audit** using the
first page prepared by the Kotlin IVEC encoder. No live NU `02/08`,
`02/02`, or `02/04` messages are sent by that action. Existing
read-only USB enumeration and IEEE 1284 device ID features remain.
The old method `experimentalNuPrint` has been redirected to the
offline audit to prevent accidental use by older callers.

The audit exports high-level metadata only, not PDF pages or raw raster
content. It records that zero USB bytes were transmitted. There is
no automatic retry and no claim that printing works.

## What is required for actual printing

1. Decode what the Windows USB driver sends in the 383-byte and
   16-byte setup exchanges, without treating captured random-looking
   payloads as reusable commands. Inspect the installed driver
   (e.g. `Driver/NUServer64.sys`, `UNTPDLL.dll`) and correlate its
   USB request structures with this PCAP.
2. If available, capture the logical USB URBs on the Windows side
   using appropriate USB tracing. A direct physical USB test capture
   may help distinguish USB printer commands from the virtual
   network-hub framing; virtual USB controllers may not appear in
   every USBPcap capture.
3. Build a state machine that constructs each command from understood
   fields, associates its response with the 16-bit transaction ID,
   and tracks claimed/busy/released device state.
4. Identify the proper output language for the connected USB-reported
   Canon `G2010 series` (04A9:183A). G2020-family IVEC is not
   automatically known to be compatible.
5. Only then run one explicitly approved physical test page, inspect
   printer state, and do not retry an uncertain delivery.

No proprietary Windows executables or captured opaque payloads should
be embedded into an Android APK. Retain GPL-3.0 compatibility.
