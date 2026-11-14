import 'dart:typed_data';

/// Offline inspection of completed NU bulk records. This is NOT a
/// transmitter: the remaining buffer contents may be Windows memory,
/// and bulk completion status semantics are still unverified.
class NuBulkRequest {
  const NuBulkRequest({
    required this.sequence,required this.endpoint,
    required this.command,required this.requestedLength,
    required this.capturedSize,
  });
  final int sequence,endpoint,command,requestedLength,capturedSize;
  bool get isOut => (endpoint&0x80)==0;
  bool get isIn => !isOut;
}
class NuBulkCompletion {
  const NuBulkCompletion({
    required this.sequence,required this.contextByte,
    required this.responseCommand,required this.reportedLength,
  });
  final int sequence,contextByte,responseCommand,reportedLength;
}
class NuBulkDecoder {
  static bool _magic(Uint8List b,int at) =>
      b.length>=at+32 && b[at]==0x55 &&
      b[at+1]==0x4e && b[at+2]==0x54 && b[at+3]==0x24;
  static bool _preamble(Uint8List b){
    if(b.length<48)return false;
    for(var i=0;i<16;i++){
      if(b[i]!=16-i)return false;
    }
    return true;
  }
  static int _be16(Uint8List b,int i)=>(b[i]<<8)|b[i+1];
  static int _le16(Uint8List b,int i)=>b[i]|(b[i+1]<<8);

  static NuBulkRequest? request(Uint8List record){
    if(!_preamble(record)||!_magic(record,16) ||
       record[22]!=2 ||
       (record[23]!=2 && record[23]!=4))return null;
    final length=_be16(record,20);
    final repeated=_le16(record,36);
    if(length!=repeated||length>4096)return null;
    final endpoint=record[32];
    if((endpoint&0x0f)==0)return null;
    return NuBulkRequest(sequence:record[24],endpoint:endpoint,
      command:record[23],requestedLength:length,
      capturedSize:record.length);
  }
  static NuBulkCompletion? completion(Uint8List record){
    if(!_magic(record,0)||record[6]!=2||
       (record[7]!=3&&record[7]!=5))return null;
    if(_be16(record,4)+32!=record.length)return null;
    if(record[26]!=0x80||record[27]!=record[8])return null;
    return NuBulkCompletion(sequence:record[8],contextByte:record[16],
      responseCommand:record[7],reportedLength:_le16(record,20));
  }
  /// Confirms a reply belongs to a request. Does not interpret its status
  /// as 'printed', 'claimed', or even successful USB transfer.
  static bool correlates(NuBulkRequest request,NuBulkCompletion reply) =>
      request.sequence==reply.sequence &&
      ((request.command==2&&reply.responseCommand==3)||
       (request.command==4&&reply.responseCommand==5));
}
