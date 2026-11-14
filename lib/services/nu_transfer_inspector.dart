import 'dart:typed_data';

/// Passive decoding of NU V1.25 USB transfer records captured on TCP 4660.
/// All offsets below are relative to the UNT$ marker, NOT the TCP segment.
/// This decoder does not construct or send any USB request.
class NuTransferRecord {
  const NuTransferRecord({
    required this.type,required this.sequence,
    required this.declaredBodyLength,required this.directionFromHub,
    required this.headerBytes,required this.usbSetup,
  });
  final int type;
  final int sequence;
  final int declaredBodyLength;
  final bool directionFromHub;
  final Uint8List headerBytes;
  final NuControlSetup? usbSetup;
}

class NuControlSetup {
  const NuControlSetup(this.requestType,this.request,this.value,
      this.index,this.length);
  final int requestType,request,value,index,length;
  bool get isGetDescriptor => requestType==0x80 && request==0x06;
  int get descriptorType => value>>8;
  int get descriptorIndex => value&255;
}

class NuTransferInspector {
  static const _magic=<int>[0x55,0x4e,0x54,0x24];
  static bool _at(Uint8List b,int i,List<int> pattern){
    if(i<0||i+pattern.length>b.length)return false;
    for(var j=0;j<pattern.length;j++){
      if(b[i+j]!=pattern[j])return false;
    }
    return true;
  }
  static int _le16(Uint8List b,int i)=>b[i]|(b[i+1]<<8);

  /// Expects a complete captured application record. The 1460-byte Windows
  /// buffers can include padding; declaredBodyLength must not be inferred
  /// from the TCP packet length.
  static NuTransferRecord? inspect(Uint8List bytes,{
    required bool fromHub,
  }) {
    final offset=fromHub?0:16;
    if(!fromHub && !_at(bytes,0,const [
      16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1]))return null;
    if(!_at(bytes,offset,_magic)||bytes.length<offset+16)return null;
    final size=_le16(bytes,offset+4);
    final type=bytes[offset+7];
    final sequence=bytes[offset+8];
    NuControlSetup? setup;
    // The observed control-transfer setup starts at UNT$+18 (request
    // direction/command), following the vendor's 18-byte envelope.
    // Scan only a small control-header window to avoid mistaking arbitrary
    // raster bytes for a setup request.
    if(!fromHub && type==0 && bytes.length>=offset+40){
      for(var i=offset+18;i+8<=offset+40;i++){
        if(bytes[i]==0x80 && bytes[i+1]==0x06){
          final length=_le16(bytes,i+6);
          if(length>0 && length<=4096){
            setup=NuControlSetup(bytes[i],bytes[i+1],
              _le16(bytes,i+2),_le16(bytes,i+4),length);
            break;
          }
        }
      }
    }
    return NuTransferRecord(type:type,sequence:sequence,
      declaredBodyLength:size,directionFromHub:fromHub,
      headerBytes:Uint8List.fromList(bytes.sublist(offset,offset+16)),
      usbSetup:setup);
  }
}
