# Additional native NU printer-class validation

The owner's Windows packet capture `plm222.pcapng` contains a USB
printer-class GET_DEVICE_ID request after the Canon USB configuration
enumeration. In USB setup terms:

- `bmRequestType = 0xA1` (device-to-host, class, interface)
- `bRequest = 0x00` (GET_DEVICE_ID)
- `wIndex = 1` (Canon printer-class interface)
- `wLength = 1009` (captured request)
- Captured reply begins with a two-byte big-endian IEEE 1284 ID length,
  followed by ASCII fields including `MFG:Canon` and `CMD:`.

The Android test now exposes an explicit **Read Canon printer-class ID**
button on the verified NU TCP session and checks the echoed NU sequence,
request type and length fields. If the hub rejects it, the session is
closed rather than continuing with potentially desynchronized framing.

Crucially, the capture's numerous 1460-byte client packets for endpoint
`0x81` are USB **IN** requests with padding. Their existence does not
show that equivalent amounts of outbound printer raster were sent. The
only observed printer-class **OUT** endpoint is `0x01`. A native print
implementation must be grounded in a separately verified bulk-OUT
request/completion exchange from a successful one-page print, along with
a suitable Canon print stream. It is **not** enabled by this change.
