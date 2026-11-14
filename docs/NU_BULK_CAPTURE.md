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
