# What the 2026-11-14 NU capture proves about bulk I/O

Examined the original 6.3 MB `plm222.pcapng` directly, deduplicating
TCP segments by sequence number in the single Windows -> hub TCP 4660 session.

The 1460-byte Windows packets are not all print data. Most carry NU bulk
IN requests for endpoint `0x81` (vendor interface 0):

| Client NU operation | Endpoint | Unique segments |
| --- | --- | ---: |
| `02/02` | 0x81 (IN) | 3036 |
| `02/04` | 0x81 (IN) | 70 |
| `02/02` | 0x01 (OUT) | 4 |
| `02/08` | 0x01 (OUT) | 2 |
| `02/00` | control endpoint 0 | 32 |

The hub replies `02/03` or `02/05` to those bulk operations; the
reply's sequence byte at `UNT$+8` matches the request. Its echoed byte at
`UNT$+27` also matches the sequence. Examples:

- Client `02/02`, seq `0x29`, endpoint `0x01`, 383 requested bytes.
- Hub `02/03`, seq `0x29`, 32-byte response. Its status semantics
  require independent validation.
- Client `02/04`, seq `0x2A`, endpoint `0x81`, 1024 requested bytes.
- Hub `02/05`, seq `0x2A`, 32-byte response.

A read request's 1460-byte transport buffer is **not proof that a
1460-byte print payload was sent**. USB printer-class interface 1 exposes
bulk OUT `0x01`, but the capture contains only four `02/02` transfers
to that endpoint, so the sample does not establish a complete
reproducible page-printing transport.

`NuBulkDecoder` now inspects captured request/completion metadata and
checks correlation. It deliberately does not transmit bulk packets or
equate a matching reply with printed output.

## Corrected analysis after Android v0.9.3 timeout (2026-11-14)

The original user's 6.3 MiB `plm222.pcapng` was reassembled in both
TCP directions, removing retransmitted segments. It contains **3,144**
client 1460-byte records after greeting and **3,163** hub replies.

An important correction: the byte `0x81` at client-record offset 32
is a **logical NU pipe identifier**, not something Android may replace
with the USB configuration descriptor's physical printer bulk IN
endpoint `0x82`. The first Windows 02/04 reads (sequences 42–44)
all use logical pipe `0x81`, and the final request bytes 44–47
are `00 12 82 24`. Android v0.9.3 incorrectly sent `0x82`
and `00 12 72 20`. Its seq42–44 reads all returned zero bytes.

The Windows reference initial transactions, *header metadata only*:

| Seq | Request | Declared bytes | NU pipe | Reply body |
| --- | --- | ---: | --- | ---: |
| 40 | 02/08 preparation | 64 | 0x01 | 32 |
| 41 | 02/02 write | 383 | 0x01 | 0 |
| 42 | 02/04 read | 1024 | 0x81 | 0 |
| 43 | 02/04 read | 1024 | 0x81 | 0 |
| 44 | 02/04 read | 1024 | 0x81 | 487 |
| 45 | 02/02 write | 16 | 0x01 | 0 |
| 46 | 02/04 read | 512 | 0x81 | 0 |
| 47 | 02/04 read | 512 | 0x81 | 24 |
| 48–50 | 02/02 writes | 4 each | 0x81 | 0 |
| 51 | 02/00 control | 8 | 0x01 | 140 |

Later there are vendor logical-pipe `0x81` writes, some 8192-byte
IN requests, additional control transfers and another preparation at
sequence 75. The bytes and statuses need decoding; it is **wrong**
to equate every 02/02 opcode with a physical printer endpoint-01
raster write. In particular the prior Android sequence 45 sent
1024 raster bytes to pipe 0x01, where Windows sent just 16 bytes.

v0.9.4 matches the first five captured NU headers and limits live
experimentation to sequences 40–44. It logs the read sizes and stops
before the proprietary 16-byte and 4-byte device exchanges that cannot
be generated from an arbitrary IVEC raster. This is a **handshake
diagnostic, not a print-job sender**. No retry is attempted on failure.
Tests use 50 actual capture metadata records without storing private
printer body or Windows binaries.
