# NU 02/08 / 02/09 out-of-order response deadlock fix

The user's Android screen showed an 8-second timeout while attempting
an experimental native NU print. The old sender sent a 02/08 setup
message and then immediately waited for a 64-byte 02/09 completion.

Reinspection of the user's original `plm222.pcapng`, with TCP segments
deduplicated by sequence number, shows:

- PC sends NU 02/08, sequence `0x28`, 1460 bytes.
- PC sends NU 02/02, sequence `0x29`, endpoint `0x01`, 383 bytes.
- Hub sends NU 02/03, sequence `0x29`, 32 bytes.
- Only later does the hub send NU 02/09, sequence `0x28`,
  64 bytes, after other NU traffic.

The previous Android sender blocked waiting for 02/09 before sending
02/02. This inverted the observed Windows sequence and may have
caused an 8-second deadlock.

The corrected experimental sender sends 02/08 then sends the raw
02/02 USB bulk OUT request without waiting for 02/09. It reads
length-prefixed NU response *frames*, handles a delayed 02/09,
and validates the 02/03 completion's sequence and transfer length.

On any timeout or unexpected response, the code reports the
request type, sequence and number of previously acknowledged
raster bytes; closes the connection; and never blindly retries.

**This is not yet a verified Canon printing driver.** The capture
does not establish all completion status fields, transfer flow control,
or an entire successful page-print session. A 02/03 completion
does not guarantee physical output. Do not repeat an uncertain
print without checking the printer and hub state.

## v0.9.3: bidirectional NU printing experiment

The sequence-43 stall happened after two 383-byte OUT completions. The
old Android sender never issued 02/04 bulk IN reads or handled the
complete 16-bit sequence field. The new implementation:

- Builds padded 1460-byte client records; hub replies are parsed as
  32-byte headers plus big-endian-declared bodies.
- Correlates 02/03, 02/05, and 02/09 replies by LE uint16 sequence, not
  arrival order.
- Starts with 02/08 preparation sequence 40, 383-byte 02/02 OUT at
  sequence 41, and three 02/04 reads at sequences 42-44.
- Uses two-OUT/two-IN windows with 1024-byte OUT data chunks thereafter.
- Provides first-48-byte TX/RX logs and per-request timeout diagnostics
  through a copyable Print tab trace.
- Disconnects on failure and never resends uncertain print bytes.

The first five operations are modeled from the described Windows capture;
the remaining 50-message test continuation is synthetic. The exact 02/04
header flags, Canon G2010 vs G2020 raster compatibility, printer status,
claim state, and end-to-end physical output remain unverified. This is
not a confirmed printing driver. 
