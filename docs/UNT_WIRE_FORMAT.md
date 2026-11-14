# DA-70251 UNT$ wire observations — 2026-11-14

This document analyzes `newtest.pcapng` included in the user's installed Windows USB Server package. Only small header excerpts and derived descriptors are documented; the capture and proprietary Windows DLLs are not checked into Git.

## Captured session boundaries

- Client `192.168.0.117` to hub `192.168.0.74`: TCP port **4660**, including separate source-port sessions **64505** and **64526**.
- Client messages begin with the 16-byte prefix `10 0F 0E 0D 0C 0B 0A 09 08 07 06 05 04 03 02 01`, followed by `55 4E 54 24` (ASCII `UNT$`).
- Server replies begin with `55 4E 54 24` **without** the 16-byte client prefix.
- In observed short server messages, bytes 4–5 are consistent with a big-endian *payload length*: 100-byte total = 32-byte common header + 68-byte payload; 58-byte total = 32 + 26; 49 = 32 + 17; 102 = 32 + 70.
- This length interpretation **does not generalize yet** to the client's 1460-byte TCP segments. Those can contain larger streams, padding or segmentation. Do not use TCP packet boundaries as protocol message boundaries.

## Clear USB enumeration data in hub responses

The 58-byte USB response includes an 18-byte standard USB device descriptor, beginning `12 01 00 02 00 00 00 40 A9 04 3A 18`. Standard USB descriptor offsets give:
- USB version 2.0;
- EP0 max packet size 64;
- idVendor **0x04A9** (Canon);
- idProduct **0x183A**;
- Manufacturer string **Canon**;
- Product string **G2010 series**, an observed USB-reported family name. The owner's physical retail model remains **Canon G2420**.

The 102-byte response includes a standard USB configuration descriptor beginning `09 02 3E 00 02 01 00 C0 01` indicating two USB interfaces. The first captured interface has class 0xFF with endpoints `0x07` (bulk OUT), `0x88` (bulk IN), and `0x89` (interrupt IN). A separate interface class 0x07 (printer) appears later in the same descriptor. **Do not hard-code endpoint 0x07 as the print endpoint** until the actual Canon interface and alternate settings are fully parsed.

## Windows transport implementation

The installed `UNTPDLL.dll` exposes mangled exports identifying `CUNTP::ConnectUSBDevice`, `DisconnectUSBDevice`, `SendConnectToDriver`, and related USB-controller driver interfaces. The binary's debug path contains `ES2868B`, supporting an Elite Silicon implementation lineage. This is **not proof** that the port 4660 wire protocol is KCodes NetUSB.

The Windows driver's virtual-host-controller and kernel drivers are needed by its original design. Reproducing the *on-wire transactions* on Android would require a full, validated message codec for claim, control transfers, bulk transfers, completion statuses, sequence IDs, disconnect and error recovery. A passive TCP probe and USB descriptor parser are not enough.

## Next engineering gate

Acquire a capture with a clearly confirmed **successful Windows USB-server connection plus a one-page Canon print**. Existing sessions show device enumeration but do not by themselves establish a safe, complete Canon print transfer sequence. The PC's native `USB Server.exe` logs can help map connect/disconnect events to packet opcodes. The uploaded ZIP contains a logging DLL (`ESTLogDLL.dll`) but **no standalone .log/.txt runtime log**.
