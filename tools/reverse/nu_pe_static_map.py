#!/usr/bin/env python3
"""Dependency-free x64 PE static map for the supplied 2011 NUServer64.sys.

This does NOT execute the driver or send printer commands.
It cross-checks .pdata function starts, debug-string xrefs and
legacy bulk-transfer instruction patterns. Requires only Python 3.
"""
import argparse
from bisect import bisect_right
import hashlib
import json
from pathlib import Path
import struct

EXPECTED = '673179777baa0bbe3ff9f1067de54ce219dcd80efd0fdad6891ca56b7dfdfcbd'
MARKERS = {
    'UsbDevicePlugIn': 0x4210,
    'CSQ_PeekNextIrp': 0x7a08,
    'BulkOrInterruptTransfer_FDO': 0x91c4,
    'SendUsbSetupPacketToDevice': 0xbf40,
    'BulkIntrTransferLegacy_IN': 0xc3ac,
    'BulkIntrTransferLegacy_OUT': 0xc5ac,
    'BulkTransferHiPerf_IN': 0xc9b4,
    'BulkTransferHiPerf_OUT': 0xcbf4,
    'GetPipeInfoStruct': 0xf728,
    'RxHiPerfCompletion': 0x109ec,
    'UserModeUsbIoCtls': 0x1cc34,
}


def analyze(path):
    data = Path(path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != EXPECTED:
        raise ValueError('Unsupported NUServer64.sys SHA-256: ' + digest)
    u16 = lambda i: struct.unpack_from('<H', data, i)[0]
    u32 = lambda i: struct.unpack_from('<I', data, i)[0]
    e = u32(0x3c)
    if data[e:e+4] != b'PE\x00\x00' or u16(e+4) != 0x8664:
        raise ValueError('Not an x64 PE file')
    opt = e + 24
    size_opt = u16(e+20)
    sections = {}
    for i in range(u16(e+6)):
        p = opt + size_opt + i*40
        name = data[p:p+8].split(b'\x00')[0].decode('ascii')
        virtual_size, rva, raw_size, raw_pos = struct.unpack_from('<IIII', data, p+8)
        sections[name] = (rva, virtual_size, raw_pos, raw_size)

    def rva_to_offset(rva):
        for a, vsize, start, n in sections.values():
            if a <= rva < a + max(vsize, n):
                return start + (rva - a)
        return None

    # Windows x64 RUNTIME_FUNCTION entries provide function boundaries.
    _, _, raw, n = sections['.pdata']
    fns = []
    for p in range(raw, raw+n-11, 12):
        start, end, unwind = struct.unpack_from('<III', data, p)
        if 0x1000 <= start < end and rva_to_offset(start) is not None:
            fns.append((start, end))
    fns.sort()
    fstarts = [a for a, _ in fns]

    def which_function(rva):
        idx = bisect_right(fstarts, rva)-1
        if idx >= 0 and rva < fns[idx][1]:
            return fns[idx]
        return None

    # Detect RIP-relative LEA/MOV xrefs from .text to debug strings.
    text_rva, _, text_offset, text_len = sections['.text']
    sec = data[text_offset:text_offset+text_len]
    string_xrefs = {}
    for i in range(len(sec)-7):
        if sec[i] in range(0x48, 0x50) and sec[i+1] in (0x8d, 0x8b) \
                and sec[i+2] & 0xc7 == 0x05:
            delta = struct.unpack_from('<i', sec, i+3)[0]
            dest_rva = text_rva + i + 7 + delta
            string_xrefs.setdefault(dest_rva, []).append(text_rva+i)

    results = {}
    for name, expected_start in MARKERS.items():
        associated = []
        for str_rva, code in string_xrefs.items():
            offset = rva_to_offset(str_rva)
            if offset is None:
                continue
            raw_string = data[offset:offset+200].split(b'\x00')[0]
            if name.lower().encode() not in raw_string.lower():
                continue
            for insn in code:
                owner = which_function(insn)
                if owner and owner[0] == expected_start:
                    associated.append({
                        'string_rva': hex(str_rva),
                        'xref_rva': hex(insn),
                        'debug_string': raw_string.decode('latin1')[:140],
                    })
        if not associated:
            raise ValueError(
                f'{name}: no string xrefs inside function RVA {expected_start:x}')
        idx = bisect_right(fstarts, expected_start)-1
        entry = fns[idx]
        if entry[0] != expected_start:
            raise ValueError(f'{name}: bad .pdata function start')
        results[name] = {
            'rva': hex(expected_start),
            'end_rva': hex(entry[1]),
            'evidence': associated[:5],
        }

    def function_bytes(name):
        rva = MARKERS[name]
        return data[rva_to_offset(rva):
                    rva_to_offset(int(results[name]['end_rva'], 16))]

    out = function_bytes('BulkIntrTransferLegacy_OUT')
    inc = function_bytes('BulkIntrTransferLegacy_IN')
    checks = {
        'legacy_out_limits_to_0x400':
            b'\xb8\x00\x04\x00\x00' in out and b'\x0f\x47\xf0' in out,
        'legacy_out_allocates_plus_0x20':
            b'\x48\x83\xc2\x20' in out,
        'legacy_out_copies_to_plus_0x20':
            b'\x48\x8d\x48\x20' in out,
        'legacy_in_limits_to_0x400':
            b'\xb8\x00\x04\x00\x00' in inc and b'\x44\x0f\x47\xc8' in inc,
    }
    if not all(checks.values()):
        raise ValueError('Unexpected legacy transfer instruction pattern')
    return {
        'file_sha256': digest, 'pe_arch': 'x86-64',
        'function_count_pdata': len(fns),
        'function_map': results,
        'disassembly_checks': checks,
        'limitations': 'Offline static evidence only; no Canon commands recovered.',
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('driver', help='path to NUServer64.sys')
    ap.add_argument('--output', help='JSON output path (default stdout)')
    args = ap.parse_args()
    rendered = json.dumps(analyze(args.driver), indent=2)
    if args.output:
        Path(args.output).write_text(rendered+'\n', encoding='utf8')
        print('Wrote '+args.output)
    else:
        print(rendered)


if __name__ == '__main__':
    main()
