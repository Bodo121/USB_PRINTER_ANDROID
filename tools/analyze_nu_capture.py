#!/usr/bin/env python3
"""Summarize NU V1.25 network traffic from a pcap or pcapng capture.

Pure Python standard library. No connection to hub, no code execution from
the archive, no Windows dependency. Payloads are NOT exported by default.

Example:
    python3 tools/analyze_nu_capture.py capture.pcapng --hub 192.168.0.74
    python3 tools/analyze_nu_capture.py capture.pcap --hub 192.168.0.74 --samples
"""
import argparse
import collections
import ipaddress
import json
import struct
from pathlib import Path


def frames_pcap(data):
    magic=data[:4]
    if magic==b"\xd4\xc3\xb2\xa1" or magic==b"\x4d\x3c\xb2\xa1":
        endian="<"
    elif magic==b"\xa1\xb2\xc3\xd4" or magic==b"\xa1\xb2\x3c\x4d":
        endian=">"
    else:
        raise ValueError("Unrecognized PCAP magic")
    if len(data)<24: raise ValueError("Truncated PCAP file")
    linktype=struct.unpack_from(endian+"I",data,20)[0] & 0xffff
    pos=24
    while pos+16<=len(data):
        _sec,_usec,included,_original=struct.unpack_from(endian+"IIII",data,pos)
        pos+=16
        if included>len(data)-pos: break
        yield linktype,data[pos:pos+included]
        pos+=included


def frames_pcapng(data):
    pos=0
    endian="<"
    links=[]
    while pos+12<=len(data):
        if data[pos:pos+4]==b"\x0a\x0d\x0d\x0a":
            bom=data[pos+8:pos+12]
            if bom==b"\x4d\x3c\x2b\x1a": endian="<"
            elif bom==b"\x1a\x2b\x3c\x4d": endian=">"
            else: raise ValueError("Invalid PCAPNG section byte order")
            links=[]
        kind,length=struct.unpack_from(endian+"II",data,pos)
        if length<12 or pos+length>len(data): break
        if struct.unpack_from(endian+"I",data,pos+length-4)[0]!=length:
            raise ValueError("Invalid PCAPNG block footer")
        body=pos+8
        if kind==1 and length>=20:
            links.append(struct.unpack_from(endian+"H",data,body)[0])
        if kind==6 and length>=32:
            iface,_,_,captured,_=struct.unpack_from(endian+"IIIII",data,body)
            start=body+20
            if iface<len(links) and captured<=length-32:
                yield links[iface],data[start:start+captured]
        pos+=length


def decode_frame(linktype,frame):
    # Ethernet, Linux SLL, raw IPv4 and loopback are the usual capture modes.
    if linktype==1:
        if len(frame)<14: return None
        etype=struct.unpack_from("!H",frame,12)[0]
        offset=14
        while etype in (0x8100,0x88a8) and len(frame)>=offset+4:
            etype=struct.unpack_from("!H",frame,offset+2)[0]
            offset+=4
        if etype!=0x800:return None
    elif linktype==113:
        if len(frame)<16 or struct.unpack_from("!H",frame,14)[0]!=0x800:return None
        offset=16
    elif linktype==101: offset=0
    else: return None
    if len(frame)<offset+20 or frame[offset]>>4!=4:return None
    ihl=(frame[offset]&0x0f)*4
    if ihl<20 or offset+ihl>len(frame):return None
    iplen=struct.unpack_from("!H",frame,offset+2)[0]
    if iplen<ihl:return None
    proto=frame[offset+9]
    if proto not in (6,17):return None
    src=str(ipaddress.IPv4Address(frame[offset+12:offset+16]))
    dst=str(ipaddress.IPv4Address(frame[offset+16:offset+20]))
    transport=offset+ihl
    end=min(len(frame),offset+iplen)
    if transport+8>end:return None
    sport,dport=struct.unpack_from("!HH",frame,transport)
    if proto==17:
        payload=frame[transport+8:end]
        typ="UDP"
    else:
        if transport+20>end:return None
        hsize=(frame[transport+12]>>4)*4
        if hsize<20 or transport+hsize>end:return None
        payload=frame[transport+hsize:end]
        typ="TCP"
    return src,dst,typ,sport,dport,payload


def summarize(data,hub,samples):
    if data[:4]==b"\x0a\x0d\x0d\x0a": frames=frames_pcapng(data)
    else: frames=frames_pcap(data)
    flows=collections.defaultdict(lambda: {"packets":0,"bytes":0,"examples":[]})
    for link,frame in frames:
        entry=decode_frame(link,frame)
        if entry is None:continue
        src,dst,typ,sport,dport,payload=entry
        if hub and hub not in (src,dst):continue
        key=(src,sport,dst,dport,typ)
        record=flows[key]
        record["packets"]+=1
        record["bytes"]+=len(payload)
        # Recognize the passive UNT$ fingerprint seen on the legacy server.
        # Only parse packet metadata: no active commands are sent.
        if payload and len(payload)>=24 and payload[16:20]==b"UNT$" and \
                payload[:16]==bytes(range(16,0,-1)):
            record["unt_signature_packets"]=record.get("unt_signature_packets",0)+1
            record.setdefault("unt_lengths",[])
            if len(record["unt_lengths"])<16:
                record["unt_lengths"].append(len(payload))
            record.setdefault("unt_byte24_values",[])
            if len(payload)>24 and len(record["unt_byte24_values"])<16:
                record["unt_byte24_values"].append(payload[24])
        if samples and payload and len(record["examples"])<3:
            record["examples"].append(payload[:48].hex(" "))
    reports=[dict(src=k[0],source_port=k[1],
      dst=k[2],destination_port=k[3],protocol=k[4],**v)
      for k,v in sorted(flows.items(),key=lambda x:-x[1]["bytes"])]
    observed_ports=sorted(set(row["destination_port"]
      for row in reports if row["dst"]==hub and row["bytes"]>0))
    return {"hub_filter":hub,
      "observed_hub_application_ports":observed_ports,
      "note":"UNT$ signatures are passive fingerprints, not a decoded USB protocol",
      "flows":reports}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("capture",type=Path)
    ap.add_argument("--hub",default="192.168.0.74",
      help="Hub IPv4 for flow filtering; use empty string for all hosts")
    ap.add_argument("--samples",action="store_true",
      help="Include up to 48 raw bytes from first three payloads per flow; may expose private data")
    ap.add_argument("--output",type=Path)
    args=ap.parse_args()
    if args.hub: ipaddress.IPv4Address(args.hub)
    data=args.capture.read_bytes()
    report=summarize(data,args.hub,args.samples)
    output=json.dumps(report,indent=2)
    if args.output:args.output.write_text(output+"\n",encoding="utf8")
    else:print(output)


if __name__=="__main__":
    main()
