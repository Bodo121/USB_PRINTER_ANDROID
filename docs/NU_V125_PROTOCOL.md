# NU V1.25 protocol research — DigitusPrint v0.6

The user's Windows utility **Networking USB Server NU V1.25** detects a USB printer attached to a DIGITUS DA-70251 / "IP USB Sharing Station" hub. The printer the user wishes to support is **Canon PIXMA G2420**, regardless of older product text shown in the hub status page.

Source: https://archive.org/details/nu-v-1.25 . This archive is a Windows installation CD, not an open protocol specification. The ISO **could not be downloaded into this analysis environment**, so the executable has **not** been disassembled or verified. The manufacturer's manual describes an "USB over IP Server" client that can connect remote USB devices, and separately describes LPR printing.

## Implemented, read-only

- The Android app can identify the USB sharing hub via its HTTP status page and probe candidate LPR queues.
- The v0.6 diagnostics probe **standard Linux USB/IP** TCP/3240 using OP_REQ_DEVLIST, and parse OP_REP_DEVLIST. This is **only one hypothesis**. Nothing establishes that NU V1.25 or DA-70251 speaks this standard; a negative result is expected for many proprietary USB sharing servers.
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
- https://ftp.assmann.com/pub/DA-/DA-70251___4016032390091/DA-70251_manual_English_20170126.pdf

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

## Inspection of user-supplied NU_V1.25(1).zip

The actual uploaded archive was inspected locally without executing the Windows installers. It is approximately 146 MiB and contains 40 ZIP members including three "Network USB Server" self-extracting executables, a Network Printer Wizard, documentation, and 2011 software release notes.

Files and SHA-256:
- `NUS_V1.25.exe` — 31,309,312 bytes — `cc413826f56c987c5c71903288fbd0ab7cb67deb91fde79e623f892de6b839bd`
- `NUS_V1.25_NPW.exe` — 37,230,080 bytes — `1b38e478976f8f6f870fd6123ac1843c4d9f6b93cbffcd7f5d3c4216b305568e`

The 31 MB `NUS_V1.25.exe` is a Microsoft Cabinet self-extractor with an embedded CAB resource. Its CAB contents were extracted **without running the installer**, and enumerate:
- `Install.exe`
- `XP64_Setup.exe`
- `XP_Setup.exe`
- `VS_Setup.exe`
- `VS_64_Setup.exe`
- `W7_Setup.exe`
- `W7_64_Setup.exe`

The nested setup packages identify themselves as **InstallShield**. Their large install payloads are packed further and the actual user-mode USB-sharing DLLs/driver binaries have **not yet been extracted**. Do not pretend these setup packages are the USB transport or that they can run on Android.

**Release-note evidence:** `SoftwareReleaseNote_0917_0049rev2_20110110.txt` describes GUI version `10_0917_0049rev2` dated 2011-01-10 and specifically fixes a bug causing an incorrect **printer queue name in the Device Properties dialog**. An earlier release `10_0917_0049` dated 2010-12-06 also fixes the incorrect Printer/MFP queue-name display. This strongly supports retaining the Windows utility's queue-identification function as a baseline, but doesn't specify how that value is calculated.

The release notes specifically refer to **E1868, E2868 and E3868 driver families**. Similar commercial products document an **Elite Silicon E3868M1** chipset, but the actual DIGITUS DA-70251's chipset **has not been verified from this ZIP**. The candidate silicon family should guide research, not be coded as fact.

**Current limitations:** The packet capture from the user contains established TCP/4660 `UNT$` client data but lacks session setup and server-side payload. The Windows installers contain the implementation, but the nested InstallShield payload has not yet been fully extracted or reverse engineered. Consequently a functioning native vendor attach / USB transfer engine **cannot responsibly be implemented from the present evidence alone**.

Next local step: inspect the installed program's actual files (after Windows installation, copy the program folder and relevant driver DLLs/SYS files; do not include unrelated private documents), or provide a capture that starts *before* the Windows utility's first connection. Look for the client packet that requests the device list, and the server's corresponding response. Native Android code must remain separate, with no Windows executable in the APK.

## Hardware model correction

Owner confirmed **DA-70251**. Refer to its own official manual: https://ftp.assmann.com/pub/DA-/DA-70251___4016032329916/ . This device supports a virtual USB server client and per-physical-port automatic connections. Do not infer its chipset or its LPR behavior from the DA-70254 manual. The observation of TCP 4660 in the uploaded capture remains valid for the *owner's actual hub*, regardless of the previous model label.

## DA-70251 Win8.1 driver and exact manual supplied by owner (2014 / 2013)

Inspected original user-uploaded files **locally without executing Windows binaries**:

- `DA-70251_driver_Driver Win8.1_20140128.zip` — 1 ZIP member, `USBServer_NPW_Setup_11_1027_0050_2015_WHQL.exe` (26,797,056 bytes).
- The executable contains a valid Microsoft CAB archive embedded at offset **60,564**. Extracted with libarchive, not by running the executable.
- Embedded CAB members:
  - `Install_OS4.exe` — 65,536 bytes
  - `XP64_Setup.exe` — 7,600,658 bytes
  - `XP_Setup.exe` — 7,245,461 bytes
  - `W7_VS_Setup.exe` — 7,254,314 bytes
  - `VS_W7_64_Setup.exe` — 7,600,055 bytes
- These nested executables are **InstallShield** setup loaders with further packed content. Directly passing them to libarchive did not expose user-mode USB client binaries or driver DLLs. Nothing in this extraction has decoded the attach/USB-URB protocol. An extracted program installation directory remains valuable.
- The separate owner's official `DA-70251_manual_English_20130422.pdf` is **54 pages**. It documents a virtual-USB utility that enumerates server/device status (pages 9–14), a four-port server configuration screen (pages 20–22), automatic printer connection (page 23), and device/port automatic connection (pages 24–26). It states the application connects a USB device as if attached directly to the PC, and releases it on disconnect.
- **Crucially, the exact DA-70251 manual contains no LPR/LPD/RFC1179 printer-queue setup instructions.** Previous LPR support claims came from the **different DA-70254** manual and should not be presented as established DA-70251 capabilities.
- The manual does **not** specify TCP port 4660, the `UNT$` wire signature, USB enumeration opcodes, device claim messages, or USB bulk transfer framing. Port 4660 and the prefix remain observations **from the owner's original PCAP**, not documented manufacturer semantics.

Research correction: **KCodes NetUSB** is a separate publicly described USB-over-IP implementation, commonly documented on TCP port 20005, whereas this DA-70251 owner's observed TCP 4660 / `UNT$` traffic and NU installer branding are different. There is currently **no demonstrated equivalence**. Do not reuse KCodes framing or assume ASIX/KCodes chipset without a verified hardware/driver identification.

**Next required evidence**: start a Wireshark capture *before* starting the Windows USB Server program, then Search, Connect Device, Disconnect Device, and stop. Capture server responses and connection setup. Alternatively supply the installed client binaries and driver files; setup executables are not those binaries. A successful print in Windows USB Server alone cannot validate Android LPR behavior.

## User-supplied installed NU client, logs and newtest.pcapng

The owner supplied `forgpete(1).zip` containing the installed `USB Server.exe`, `UNTPDLL.dll`, `DCPDLL.dll`, `PSMDLL.dll`, Windows driver `.sys` files, `Config.ini`, `log.txt`, and `newtest.pcapng`. This is substantially more useful than the installer archive.

The 2026-11-14 Windows log records `[PSM] ConnectDevice <C0A8004A_9B0767DD>[0] ID=3000`, `TryConnectDevice ... Ret=1`, then `ID=3000_End`. `C0A8004A` represents 192.168.0.74. The GUI logs a device identify string `04A9:183A:9B0767DD:019249` (Canon VID 04A9, PID 183A, hub suffix 9B0767DD, serial 019249). These are *application log statuses*, not proof that a USB transfer or printed page completed.

New network capture analysis found a `DCP$` UDP protocol with hub response containing an `EST$` section, server name, MAC and physical socket count. The 1059-byte response in the capture is the basis of the passive Dart parser and test. This discovery protocol is distinct from the still-unresolved `UNT$` TCP 4660 USB transfer framing.

**Remaining:** decode and verify client-to-hub DCP request, successful TCP session establishment, device-claim and URB/bulk transfer framing from the capture/binaries. Do not infer that USB claim is working from a positive application log return value.

## Packet-level findings from plm222.pcapng and v0.9.1 diagnostics (14 Nov 2026)

Re-parsed original owner capture directly, using PCAPNG enhanced-packet blocks, IPv4 TCP sequence numbers and UDP payloads. Unlike earlier traces, it begins with a live TCP connection to the physical DA-70251. Distinct sample frames below are taken from the actual capture; TCP application payloads are listed by direction and start length; TCP segments may include retransmissions.

**Active UDP discovery (Windows PC 192.168.0.117 → hub 192.168.0.74):**
- Source UDP 52340 → hub UDP 52330, 40-byte query:
  `44 43 50 24 00 00 00 0d 62 b9 00 00 cc 74 02 00`, followed by 24 zero bytes.
- `DCP$` is ASCII at offset 0, command `00 00 00 0d` at 4..7, per-query correlation token at 8..9, source port `cc 74` (=52340) at 12..13, `02 00` at 14..15.
- Hub responds UDP 52330 → PC UDP 52340 with 1059-byte `DCP$` result. Response echoes correlation token, includes MAC at offset 16, physical-port count at 32, station name at 40, `EST$` at 104, IPv4 at 114, and nested device `DCP$` at 176. Device name `G2010 series` at 200, `Canon` at 232, serial `019249` at 272.
- **Implementation:** `DcpDiscovery.discover` sends this 40-byte observed request with a fresh 16-bit token, listens on matching UDP source port and validates response token/IP/source.

**First TCP greeting, TCP 4660 (observed, not speculative):**
- Client's first application payload is **116 bytes**. Offsets 0..15: `10 0f 0e 0d 0c 0b 0a 09 08 07 06 05 04 03 02 01`; 16..19: `UNT$`; 20..27: `00 44 02 0a 14 00 80 00`; offset 32: `02`; offset 48: Windows computer name, NUL-terminated; offsets 112..115: local IPv4.
- Hub's first response is **100 bytes**: `55 4e 54 24 00 44 00 0b 14 00 80 00` followed by similar computer-name and local-IP fields.
- This suggests a 16-byte client preamble, a 32-byte base header and a variable payload, but exact field semantics are not completely proven.
- **Implementation:** `NuSessionDiagnostics.greeting` sends only this initial greeting using an Android client name and the phone's LAN IPv4; it validates the 100-byte response and immediately closes. It does NOT claim a USB port or queue a transfer; the user must run it manually.

**Confirmed subsequent USB control exchange in capture:**
- After greeting, Windows sends a TCP payload of **1460 bytes** with the 16-byte prefix, `UNT$ 00 08 02 00 15 00 ...`; hub replies with **58 bytes**: `UNT$ 00 1a 02 01 15 00 ...` and visible standard USB descriptor data `12 01 00 02 ... a9 04 3a 18` indicating Canon USB VID `04A9`, PID `183A`.
- Following messages request USB configuration and UTF-16LE string descriptors (Canon / G2010 series / serial), then receive bounded responses.
- In a later active data exchange, Windows sends `UNT$ ... 02 04` and hub responds with `UNT$ ... 02 05` (including 32-byte responses), consistent with paired requests/completions, but *not enough evidence* to declare all endpoint, URB, error, length and toggle semantics.
- Client application payloads frequently appear as **1460-byte segments** regardless of a much smaller declared body size; do not assume these are discrete USB transfer packets or blindly replay fixed 1460-byte buffers.
- The captured approximately 4.59 MiB PC→hub demonstrates substantial activity, but it is not independent proof of printed paper or compatible Canon IVEC/PWG output.

**Remaining before enabling native USB printing:** confirm exact URB request framing/endpoint semantics and response status, transfer completion/short packets and retries, attach/exclusive-use and disconnect behavior, and verify raster bytes physically on G2420. As of v0.9.1, no Android USB print job is sent over TCP 4660. This is a partial protocol implementation, not a complete replacement for the Windows USB stack.
