# NU V1.25 connection / printing implementation status

Evidence: owner's `plm222.pcapng` (Windows PC 192.168.0.117 -> hub 192.168.0.74:4660).

## Verified on real Android hardware
- DCP discovery returned hub MAC and Canon device information.
- A 116-byte TCP client greeting received a 100-byte UNT$ greeting response.

## Capture findings
- Client greeting starts with 16 descending bytes, then `UNT$`.
- Hub greeting begins directly with `UNT$`.
- Subsequent traffic includes USB GET_DESCRIPTOR control setup `80 06 00 01`, `80 06 00 02` and USB string descriptor requests.
- Later messages include additional transport command types and bulk-size payloads.
- The capture includes retransmissions and TCP segmentation. A TCP segment must not be interpreted as exactly one vendor frame.

## Implementation gates before enabling live printer claiming
1. Reassemble TCP streams and establish exact NU frame length, transaction-ID, command and completion-status semantics.
2. Correlate Windows device claim / release events with packets, distinguishing successful attachment from enumeration and print data.
3. Validate exclusive-ownership checks, busy response, timeouts, cancellation and release.
4. Verify USB control endpoint zero descriptor retrieval on Android after claiming.
5. Identify the Canon bulk OUT endpoint, chunking and transfer-completion acknowledgment.
6. Run an explicit one-page print test with reliable disconnect and reconnect.

Do not replay arbitrary captured URBs: they contain transaction IDs, buffer lengths and state that are specific to the Windows session.

Current app supports discovery and NU greeting; it does not yet implement validated claim, USB bulk transfers, or printing through the vendor transport.
