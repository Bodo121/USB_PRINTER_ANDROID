# Canon G2010/G2420 USB configuration decoded from plm222.pcapng

The TCP 4660 Windows capture has a clean, loss-free NU stream. After the
116-byte greeting and matching 100-byte reply, a sequence of 1460-byte
client records and variable-length hub replies contains three standard
USB configuration-descriptor transfers:

* Sequence 0x15: USB GET_DESCRIPTOR(Device), reply 58 bytes,
  USB VID:PID `04a9:183a`.
* Sequence 0x16: USB GET_DESCRIPTOR(Configuration), 9-byte header,
  reply 49 bytes.
* Sequence 0x17: USB GET_DESCRIPTOR(Configuration), 62-byte complete
  descriptor, reply 102 bytes.

The complete configuration descriptor (hex):
```
09 02 3e 00 02 01 00 c0 01
09 04 00 00 03 ff 00 ff 00
07 05 07 02 00 02 00
07 05 88 02 00 02 00
07 05 89 03 40 00 0b
09 04 01 00 02 07 01 02 00
07 05 01 02 00 02 00
07 05 82 02 00 02 00
```

Interface 0, class FF (vendor-specific): bulk OUT 07, bulk IN 88,
interrupt IN 89. Interface 1, class 07 (printer), subclass 01,
protocol 02: bulk OUT 01, bulk IN 82. Both bulk endpoints have 512-byte
maximum packet size.

The new Android NU test now reads these descriptors and validates the
printer-class interface and its bulk OUT endpoint against the live hub.
This is read-only USB enumeration, **not a verified exclusive claim**.

## Why print is not enabled yet
The trace contains 3040 NU 02/02 requests and matching 02/03 completions,
with NU 02/04 read requests and 02/05 read responses. The bulk
requests include 1460-byte TCP buffers, many with zero-padded unused
space; their reported lengths and internal request IDs are not fully
mapped. There is no verified dynamic USB transfer API, printer interface
claim confirmation, endpoint selection handshake, nor guaranteed vendor
release command. Replaying the Windows request buffers as printing
commands would be unjustified. The existing Android LPR print path
is unrelated to this successful USB control-transfer path.

When a validated native bulk print sender is added, it must obtain the
print-ready Canon raster bytes from the Android encoder, segment them
according to confirmed NU bulk frame semantics, verify each completion
and then release the device, with explicit cancellation and no blind retry.
