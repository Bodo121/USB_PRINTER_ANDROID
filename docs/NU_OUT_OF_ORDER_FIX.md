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
