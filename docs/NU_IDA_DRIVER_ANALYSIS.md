# NUServer64.sys: static disassembly and IDA preparation

## Evidence

Examined the user's original forgpete(1).zip, specifically
Driver/NUServer64.sys, using x64 objdump and an independent Python
PE parser. The original archive is not redistributed in this repo.

- NUServer64.sys SHA-256: 673179777baa0bbe3ff9f1067de54ce219dcd80efd0fdad6891ca56b7dfdfcbd
- UNTPDLL.dll SHA-256: c08f089e4be22a13cac43f25e77821da95a5db4032442824068175c702e8be87
- NPWuntp.dll SHA-256: 8fdce4317571514c1301a6cc840e3f5bd740afb638de22ed12eeafc2fb5abff7

The x64 PE .pdata table has 312 usable runtime-function entries.
RIP-relative references to embedded driver logging strings associate
the following routine names with verified start RVAs:

| Driver routine | RVA | Evidence |
| --- | --- | --- |
| UsbDevicePlugIn | 0x4210 | Opens legacy or separate high-performance command/data sockets |
| CSQ_PeekNextIrp | 0x7A08 | Lookup by sequence, command, port, endpoint |
| BulkOrInterruptTransfer_FDO | 0x91C4 | Routes USB bulk transfers |
| SendUsbSetupPacketToDevice | 0xBF40 | Sends USB control/setup packets |
| BulkIntrTransferLegacy_IN | 0xC3AC | Legacy USB read request |
| BulkIntrTransferLegacy_OUT | 0xC5AC | Legacy USB write request |
| BulkTransferHiPerf_IN | 0xC9B4 | High-performance USB read |
| BulkTransferHiPerf_OUT | 0xCBF4 | High-performance USB write |
| NU legacy header constructor | 0xF05C | Constructs a 32-byte UNT$ header |
| GetPipeInfoStruct | 0xF728 | USB pipe lookup |
| RxHiPerfCompletion | 0x109EC | Matches outstanding high-performance IRPs |
| UserModeUsbIoCtls | 0x1CC34 | User-mode USB IOCTL bridge |

These are relative virtual addresses in THIS binary, not absolute
addresses, and may differ in other versions.

## Concrete transfer result from x64 assembly

The function at RVA 0xC5AC (BulkIntrTransferLegacy_OUT) reads
the client USB transfer length and offset. Its relevant instructions:

    RVA C631: sub esi, r10d         ; remaining bytes = length-offset
    RVA C64C: mov eax, 0x400       ; 1024 bytes
    RVA C651: cmp esi, eax
    RVA C653: cmova esi, eax       ; fragment <= 1024
    RVA C658: lea rdx, [rsi+0x20] ; allocate length + 32
    RVA C67B: lea rcx, [rax+0x20] ; buffer payload after header
    RVA C68A: call 0x1D9B0        ; transfer-buffer copying helper
    RVA C6B0: call 0xF05C         ; header builder
    RVA C719: call send path

The corresponding legacy IN function at RVA 0xC3AC also clamps
the requested USB fragment to 0x400 at RVAs 0xC45B..0xC46B.

At RVA 0xF09D the header builder writes the magic UNT$
(DWORD immediate 0x24544e55) at the start of a 32-byte buffer.
Other fields depend on device and IRP context, not just opcode.

**The important implication**: the 383-byte payload at sequence 41
comes from an upper-layer USB client transfer buffer. The NU driver's
legacy-OUT path does not synthesize an authentication challenge there.
The payload could be a Canon printer command or other USB client data;
its precise semantics are still unknown. We must not call it encrypted
without stronger evidence or substitute bytes from a different IVEC
XML job.

## Correlation with the successful Windows network capture

Reassembled the user's plm222.pcapng, deduplicating TCP retransmissions.

- Windows seq41: 383-byte 02/02 to logical NU pipe 0x01.
- Seq42 and 43: 1024-byte 02/04 reads on logical NU pipe 0x81,
  each with zero actual USB data returned.
- Seq44: another 1024-byte read, this time 487 bytes returned.
- Seq45: a 16-byte 02/02, not an arbitrary 1024-byte raster chunk.
- Seq46/47: two 512-byte 02/04 reads.
- Later sequences include logical pipe 0x81 traffic, USB control
  operations, and 8192-byte reads in a different transfer context.

Windows client TCP records are 1460 bytes: 16-byte preamble +
32-byte NU header + a capacity/padding area. The outer record size
does not prove that the client transferred 1412 USB bytes. Some
02/04 record padding includes stale data from previous requests:
do not retransmit that stale data as if it were a read command.

A zero-length reply is not automatically failure. The successful
Windows trace contains empty seq42/43 reads before a data-bearing
seq44 reply. Error/NAK/status flags remain to be decoded.

## Implemented

1. tools/reverse/nu_pe_static_map.py: dependency-free offline
   PE function/xref/instruction-signature verifier. **Executed
   successfully** against the exact user's 2011 NUServer64.sys.
2. tools/reverse/nu_ida_analysis.py: SHA-guarded IDAPython 7.7+
   function naming, comments and JSON call/xref mapping.
   **Not executed inside IDA** here because IDA is unavailable.
3. lib/services/nu_legacy_fragmenter.dart: pure Dart, offline model
   of the recovered 1024-byte legacy USB fragment allocation
   (payload length + 32). Flutter tests cover 383, 1024, 2049,
   partial-offset and empty transfers.
4. Actual Digitus Print printer output remains OFFLINE_ONLY.
   No arbitrary binary packet replay and no automatic retry.

## Reproduce

Extract the owner's original driver archive. Run this in Python 3:

    python3 tools/reverse/nu_pe_static_map.py path/to/NUServer64.sys --output nu_pe_map.json

To see annotated decompilation and call graphs, open NUServer64.sys
in IDA as x64 PE, allow full autoanalysis, then use
File -> Script file -> tools/reverse/nu_ida_analysis.py.
The script creates nu_ida_analysis.json in the driver directory or
in a temporary directory if the original isn't writable.

## Still needed for printing

Identify how the Canon Windows printer driver generates the original
383-byte USB message and later print stream; verify the correct
G2010-compatible raster profile. Then decode 02/03 and 02/05
completion status and implement proper pipe/IRP state tracking.
High-performance completion handling is not necessarily the same
as the legacy 4660 printer session. Until these are understood,
live printing must remain disabled.
