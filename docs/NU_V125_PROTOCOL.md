# NU V1.25 protocol research — DigitusPrint v0.6

The user's Windows utility **Networking USB Server NU V1.25** detects a USB printer attached to a DIGITUS DA-70254 / "IP USB Sharing Station" hub. The printer the user wishes to support is **Canon PIXMA G2420**, regardless of older product text shown in the hub status page.

Source: https://archive.org/details/nu-v-1.25 . This archive is a Windows installation CD, not an open protocol specification. The ISO **could not be downloaded into this analysis environment**, so the executable has **not** been disassembled or verified. The manufacturer's manual describes an "USB over IP Server" client that can connect remote USB devices, and separately describes LPR printing.

## Implemented, read-only

- The Android app can identify the USB sharing hub via its HTTP status page and probe candidate LPR queues.
- The v0.6 diagnostics probe **standard Linux USB/IP** TCP/3240 using OP_REQ_DEVLIST, and parse OP_REP_DEVLIST. This is **only one hypothesis**. Nothing establishes that NU V1.25 or DA-70254 speaks this standard; a negative result is expected for many proprietary USB sharing servers.
- This diagnostic never issues USB/IP OP_REQ_IMPORT, never connects to USB endpoints, and never sends data to the printer.
- Android remains native: Flutter UI with Dart network discovery and Kotlin Canon IVEC raster output.

## Capturing the actual Windows utility protocol

A successful Windows detection is very helpful but **does not reveal the bytes of its device-discovery handshake**. To reproduce NU V1.25 precisely, capture its traffic rather than guessing.

1. Connect PC and DIGITUS hub to the same private LAN, with the hub at `192.168.0.74`.
2. Start Wireshark capture on the active Ethernet/Wi-Fi interface. Close unrelated apps first.
3. Launch "USB Server" from NU V1.25, click **Search**. Wait for the printer to appear.
4. Select it and click **Connect Device**, then **Disconnect Device**. Avoid printing sensitive documents.
5. Stop recording and save as `nu-v125-canon.pcapng`. Before sharing, consider trimming/filtering the capture to packets involving the hub.
6. Analyze with `python3 tools/analyze_nu_capture.py nu-v125-canon.pcapng --hub 192.168.0.74`.
7. For protocol signatures only, use `--samples` to include the first 48 payload bytes from flows. Check these samples before sharing because they can include sensitive data.

The analyzer works offline on PCAP/PCAPNG files, using Python standard library, and reports only network endpoint/port/packet-volume statistics by default. It supports Ethernet, Linux cooked captures, and raw IPv4. It doesn't attempt TCP reassembly or decryption.

## Next step to implement real vendor USB transfer

Identify the discovery broadcast/unicast destination, vendor TCP/UDP ports, command opcodes, device catalog, and attach/exclusive-use handshake from the capture. Model parser must handle variable lengths, timeouts, checksum/sequence fields, and locked-device status. Only after validation should it implement USB bulk/control transfer framing for Canon IVEC and status feedback.

Do **not** assume this is Linux USB/IP, blindly send USB URBs to unverified devices, or report "Canon ready" from a hub's USB online state. Do not bundle Windows DLLs or drivers in the Android APK.

## Sources

- https://archive.org/details/nu-v-1.25
- https://www.kernel.org/doc/html/v5.18/usb/usbip_protocol.html
- https://ftp.assmann.com/pub/DA-/DA-70254___4016032390091/DA-70254_manual_English_20170126.pdf

## Findings from user capture `printer.pcapng` (2026-11-14)

The supplied 52 MiB PCAPNG was parsed locally, filtering IP packets involving the hub at `192.168.0.74`. It includes a large amount of unrelated public Internet TLS traffic. The capture **must not be committed raw**.

**Confirmed:**

- Windows host `192.168.0.117` communicates with the hub `192.168.0.74` on **TCP port 4660**, from client TCP source port `50531`.
- Exactly **8 observed client TCP payload segments**, each **1,460 bytes**, total **11,680 payload bytes**, approximately 9.07 seconds apart.
- Each starts with `10 0f 0e 0d 0c 0b 0a 09 08 07 06 05 04 03 02 01 55 4e 54 24` (ASCII **`UNT$`** at offset 16).
- A byte near offset 24 increments `57,58,59,5a,5b,5c,5d,5e`. This is *consistent with* a counter but **the field semantics are unverified**. Most of each message consists of zero bytes.
- The hub emitted 544 captured TCP packets in this flow, **no TCP application payload** within those packets; the PC appears to have captured an established session *after* its initial handshake.
- No UDP traffic from the PC to local broadcast/discovery destinations was seen in the captured interval; no USB attach handshake or device-list response is present.

**Interpretation:** TCP 4660 is a strong vendor-protocol candidate for this network USB hub. It is **not** LPR TCP 515 and **not** Linux USB/IP TCP 3240. The observed client messages have a `UNT$` signature. Neither their meaning nor the complete protocol has been established; they must **not** be replayed as USB commands.

**Next focused capture:** close the Windows utility completely; start Wireshark **before opening** the utility; apply display filter `ip.addr == 192.168.0.74 || udp` to inspect discovery broadcasts; then launch the utility, click Search, Connect Device, Disconnect Device, and stop capture. Capture the TCP SYN/handshake and both-direction application data. With this, infer whether TCP 4660 is an attach/data channel or only a polling/keepalive channel. If the hub is already connected, explicitly disconnect first. A 30–60-second focused trace is more useful and privacy-friendly than a general long capture.

Do not infer Canon model or LPR queue from the `UNT$` stream. The printer remains user-configured **Canon PIXMA G2420**.
