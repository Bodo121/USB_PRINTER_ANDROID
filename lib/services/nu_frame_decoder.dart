import 'dart:typed_data';

/// Offline-only framing analysis for the proprietary DA-70251 NU transport.
/// Unlike standard Linux USB/IP, the observed messages carry an UNT$ marker
/// after a 16-byte client preamble. The header field meanings are still
/// unknown; never transmit these packets to a live hub.
class NuFrame {
  const NuFrame({required this.clientPreamble,required this.markerOffset,
    required this.rawHeader,required this.payloadLength,
    required this.candidateOpcode,required this.candidateSequence});
  final bool clientPreamble;
  final int markerOffset;
  final Uint8List rawHeader;
  final int payloadLength;
  final int? candidateOpcode;
  final int? candidateSequence;
}

class NuFrameDecoder {
  static const marker=<int>[0x55,0x4e,0x54,0x24];
  static const preamble=<int>[
    0x10,0x0f,0x0e,0x0d,0x0c,0x0b,0x0a,0x09,
    0x08,0x07,0x06,0x05,0x04,0x03,0x02,0x01
  ];

  static bool _matches(Uint8List bytes,int offset,List<int> pattern){
    if(offset+pattern.length>bytes.length)return false;
    for(var i=0;i<pattern.length;i++){
      if(bytes[offset+i]!=pattern[i])return false;
    }
    return true;
  }

  /// Accepts a *reassembled* TCP application message, not an arbitrary
  /// 1460-byte segment. Both observed Windows and hub framing are supported.
  static NuFrame? inspect(Uint8List bytes){
    if(bytes.length<20||bytes.length>16*1024*1024)return null;
    final client=_matches(bytes,0,preamble);
    final offset=client?16:0;
    if(!_matches(bytes,offset,marker))return null;
    final available=bytes.length-offset;
    if(available<16)return null;
    final header=Uint8List.fromList(bytes.sublist(offset,offset+16));
    // Offsets are deliberately only candidates pending cross-session
    // correlation. Never use these fields to construct USB commands.
    return NuFrame(clientPreamble:client,markerOffset:offset,
      rawHeader:header,payloadLength:available-16,
      candidateOpcode:(header[4]<<8)|header[5],
      candidateSequence:header[8]);
  }
}
