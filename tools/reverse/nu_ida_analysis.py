"""
IDAPython 7.7+/8+/9+ static analysis aid for NUServer64.sys (2011 x64).
Run with File -> Script file in IDA after auto-analysis completes.

This script DOES NOT execute any Windows driver, transmit USB commands,
decrypt data, or claim that printer authentication has been decoded.
It renames known functions from proven string xrefs and x64 .pdata,
adds disassembly-backed comments, and exports a JSON call/xref map.

Intended input SHA-256:
673179777baa0bbe3ff9f1067de54ce219dcd80efd0fdad6891ca56b7dfdfcbd
"""
import hashlib
import json
import os
import tempfile

import ida_auto
import ida_bytes
import ida_funcs
import ida_nalt
import ida_name
import idautils
import idc

EXPECTED_SHA256 = (
    "673179777baa0bbe3ff9f1067de54ce219dcd80efd0fdad6891ca56b7dfdfcbd"
)

# All addresses are RVAs relative to NUServer64.sys's PE image base,
# not hard-coded virtual addresses. Confirmed against .pdata boundaries
# and x64 RIP-relative references to debug strings.
FUNCTIONS = [
    ("NU_UsbDevicePlugIn",             0x04210, "UsbDevicePlugIn"),
    ("NU_CSQ_PeekNextIrp",             0x07A08, "CSQ_PeekNextIrp"),
    ("NU_BulkOrInterruptTransfer_FDO", 0x091C4, "BulkOrInterruptTransfer_FDO"),
    ("NU_SendUsbSetupPacketToDevice", 0x0BF40, "SendUsbSetupPacketToDevice"),
    ("NU_BulkIntrTransferLegacy_IN",   0x0C3AC, "BulkIntrTransferLegacy_IN"),
    ("NU_BulkIntrTransferLegacy_OUT",  0x0C5AC, "BulkIntrTransferLegacy_OUT"),
    ("NU_BulkTransferHiPerf_IN",       0x0C9B4, "BulkTransferHiPerf_IN"),
    ("NU_BulkTransferHiPerf_OUT",      0x0CBF4, "BulkTransferHiPerf_OUT"),
    ("NU_BuildLegacyHeader",           0x0F05C, None),
    ("NU_GetPipeInfoStruct",           0x0F728, "GetPipeInfoStruct"),
    ("NU_RxHiPerfCompletion",          0x109EC, "RxHiPerfCompletion"),
    ("NU_UserModeUsbIoCtls",           0x1CC34, "UserModeUsbIoCtls"),
]

NOTES = {
    "NU_BulkIntrTransferLegacy_OUT": (
        "Disassembly-backed: the function reads a USB-client transfer "
        "buffer and offset, computes remaining bytes, clamps this fragment "
        "to 0x400 (1024), allocates chunk_length+0x20, copies source "
        "bytes into buffer+0x20, calls the 32-byte header builder and "
        "submits a transport send. The opaque seq41 payload is forwarded "
        "USB-client data, not generated from constants in this function."
    ),
    "NU_BulkIntrTransferLegacy_IN": (
        "Disassembly-backed: clamps an IN request fragment to 0x400 "
        "(1024) and constructs a 32-byte legacy request header. Zero-"
        "length read responses must be evaluated with status/URB context."
    ),
    "NU_BuildLegacyHeader": (
        "RVA 0xF05C writes 'UNT$' as DWORD 0x24544e55 at buffer+0, "
        "sets several packed flags and copies sequence/length arguments "
        "into the 32-byte header. Layout is context-dependent; do not "
        "copy observed bytes into a live request without interpreting "
        "the URB, USB configuration and endpoint selection."
    ),
    "NU_RxHiPerfCompletion": (
        "Looks up original IRP by 16-bit sequence number and reacts to "
        "USB halt/error flags. High-performance completion behavior is "
        "not a drop-in replacement for legacy TCP/4660 02/03 replies."
    ),
}

def sha256_of_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as src:
        for chunk in iter(lambda: src.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def main():
    ida_auto.auto_wait()
    source = idc.get_input_file_path()
    if not source or not os.path.isfile(source):
        raise RuntimeError("Original NUServer64.sys missing. Load the "
                           "2011 driver binary and keep its source path.")
    digest = sha256_of_file(source)
    if digest.lower() != EXPECTED_SHA256:
        raise RuntimeError("Driver hash mismatch: " + digest +
                           ". RVAs are only verified for this exact version.")
    image_base = ida_nalt.get_imagebase()

    # Construct a reverse index of only relevant debug strings.
    hints = {}
    needles = [marker.lower() for _, _, marker in FUNCTIONS if marker]
    for item in idautils.Strings():
        value = str(item)
        if any(n in value.lower() for n in needles):
            hints.setdefault(item.ea, value)

    functions = []
    for symbol, rva, marker in FUNCTIONS:
        ea = image_base + rva
        fn = ida_funcs.get_func(ea)
        if fn is None or fn.start_ea != ea:
            raise RuntimeError(
                "Function boundary mismatch at RVA 0x%X (%s); "
                "check x64 .pdata and autoanalysis first" % (rva, symbol)
            )
        ida_name.set_name(ea, symbol, ida_name.SN_CHECK)
        if symbol in NOTES:
            ida_funcs.set_func_cmt(fn, NOTES[symbol], True)

        string_evidence = []
        for string_ea, value in hints.items():
            if marker and marker.lower() not in value.lower():
                continue
            xrefs = [x.frm for x in idautils.XrefsTo(string_ea, 0)]
            matched = [x for x in xrefs if fn.start_ea <= x < fn.end_ea]
            if matched:
                string_evidence.append({
                    "string_rva": hex(string_ea - image_base),
                    "xrefs_rva": [hex(x - image_base) for x in matched],
                    "value": value[:160],
                })

        calls = set()
        for insn_ea in idautils.FuncItems(ea):
            mnemonic = idc.print_insn_mnem(insn_ea).lower()
            if mnemonic.startswith("call"):
                for target in idautils.CodeRefsFrom(insn_ea, 0):
                    calls.add((target - image_base, idc.get_func_name(target)))
        functions.append({
            "name": symbol,
            "rva": hex(rva),
            "size": fn.end_ea - fn.start_ea,
            "string_xrefs": string_evidence,
            "calls": [
                {"rva": hex(rva2), "name": name}
                for rva2, name in sorted(calls)[:100]
            ],
            "note": NOTES.get(symbol, ""),
        })

    data = {
        "driver": os.path.basename(source),
        "sha256": digest,
        "image_base": hex(image_base),
        "method": "IDA PE x64 .pdata + debug-string xrefs + call graph",
        "functions": functions,
        "caveat": (
            "Static analysis only. No printer command generator or "
            "driver-complete NU protocol has been recovered."
        ),
    }
    dest = os.path.join(os.path.dirname(source), "nu_ida_analysis.json")
    try:
        with open(dest, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except OSError:
        dest = os.path.join(tempfile.gettempdir(), "nu_ida_analysis.json")
        with open(dest, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    print("[NU reverse engineering] annotated %d functions; JSON: %s" %
          (len(functions), dest))

if __name__ == "__main__":
    main()
