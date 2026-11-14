import 'dart:typed_data';

/// Experimental NU TCP 4660 client records. Never replay raw Windows URBs.
/// The nonstandard flags are reconstructed from one capture, not validated
/// as a complete printer driver.
class NuWire {
  static const int recordSize=1460;
  static const int maxData=1412;
  static const preamble=<int>[16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1];

  static Uint8List _request(int op,int seq,int ep,int count,Uint8List? bytes) {
    if(seq<0||seq>65535)throw const FormatException('Sequence exceeds uint16');
    if(ep<1||ep>255||count<1||count>maxData){
      throw const FormatException('Invalid NU endpoint or count');
    }
    if(!<int>[2,4,8].contains(op) || (op==2)!=(bytes!=null) ||
       (bytes!=null && bytes.length!=count)){
      throw const FormatException('Invalid NU operation or payload');
    }
    final b=Uint8List(recordSize);
    b.setAll(0,preamble);
    b.setAll(16,const <int>[85,78,84,36]);
    b[20]=count>>8;b[21]=count&255;
    b[22]=2;b[23]=op;
    b[24]=seq&255;b[25]=(seq>>8)&255;
    b[30]=1; b[32]=ep;
    b[36]=count&255;b[37]=(count>>8)&255;
    b[42]=0x80;b[43]=seq&255;
    if(op==8) {
      b[34]=0x0b;b[40]=0x04;b[41]=0xf8;
      b.setAll(44,const <int>[0x40,0x10,0x92,0x34]);
    } else {
      b[34]=0x30;b[35]=0xf0;
      b.setAll(44,const <int>[0,0x12,0x72,0x20]);
    }
    if(bytes!=null)b.setRange(48,48+bytes.length,bytes);
    return b;
  }

  static Uint8List bulkOut(Uint8List bytes,{required int sequence,int endpoint=1}) =>
    _request(2,sequence,endpoint,bytes.length,bytes);

  /// 02/04 read metadata layout remains provisional; use the enumerated
  /// printer-class IN endpoint, not an unrelated interface's endpoint.
  static Uint8List bulkIn({required int sequence,required int endpoint,
      int requestedLength=1024}) =>
    _request(4,sequence,endpoint,requestedLength,null);

  static Uint8List prepare({required int sequence,int endpoint=1}) =>
    _request(8,sequence,endpoint,64,null);

  static int txSequence(Uint8List b) {
    if(b.length!=recordSize||b[16]!=85||b[17]!=78||b[18]!=84||b[19]!=36 ||
       !List<int>.generate(16,(i)=>16-i).asMap().entries.every(
         (e)=>b[e.key]==e.value)){
      throw const FormatException('Invalid NU client frame');
    }
    return b[24]|(b[25]<<8);
  }

  static String hex(Uint8List b,{int limit=48}) =>
    b.take(limit).map((v)=>v.toRadixString(16).padLeft(2,'0')).join(' ');
}

class NuReply {
  const NuReply._(this.raw,this.command,this.sequence,this.bodyLength,
      this.reportedLength);
  final Uint8List raw;
  final int command,sequence,bodyLength,reportedLength;
  static NuReply parse(Uint8List b) {
    if(b.length<32||b[0]!=85||b[1]!=78||b[2]!=84||b[3]!=36||b[6]!=2){
      throw const FormatException('Invalid NU response header');
    }
    final len=(b[4]<<8)|b[5];
    if(b.length!=32+len||len>4096){
      throw const FormatException('Invalid NU response body length');
    }
    return NuReply._(b,b[7],b[8]|(b[9]<<8),len,b[20]|(b[21]<<8));
  }
  String get summary=>'02/'+command.toRadixString(16).padLeft(2,'0')+
    ' seq='+sequence.toString()+' body='+bodyLength.toString()+
    ' reported='+reportedLength.toString();
}

class NuPending {
  const NuPending(this.command,this.sequence,this.requested,this.created,
      this.timeout);
  final int command,sequence,requested;
  final DateTime created;
  final Duration timeout;
  DateTime get deadline=>created.add(timeout);
}

/// Matches 02/03, 02/05, 02/09 by uint16 LE sequence, not response order.
class NuPendingReplies {
  final _pending=<int,NuPending>{};
  bool get isEmpty=>_pending.isEmpty;
  bool get hasDataPending=>_pending.values.any((p)=>p.command!=8);
  int get length=>_pending.length;
  Iterable<NuPending> get values=>_pending.values;
  NuPending? get oldest {
    NuPending? candidate;
    for(final p in _pending.values){
      if(candidate==null||p.deadline.isBefore(candidate.deadline))candidate=p;
    }
    return candidate;
  }
  void add(int op,int seq,int count,{DateTime? now,
      Duration timeout=const Duration(seconds:12)}) {
    if(!<int>[2,4,8].contains(op)||seq<0||seq>65535||
       _pending.containsKey(seq)){
      throw StateError('Invalid or duplicate pending NU sequence');
    }
    _pending[seq]=NuPending(op,seq,count,now??DateTime.now(),timeout);
  }
  NuPending accept(NuReply r){
    final p=_pending[r.sequence];
    if(p==null)throw FormatException('Unmatched NU '+r.summary);
    if(r.command!=p.command+1){
      throw FormatException('Unexpected NU reply '+r.summary+
        ' expected '+(p.command+1).toString());
    }
    if(p.command==2&&(r.bodyLength!=0||r.reportedLength!=p.requested)){
      throw FormatException('NU OUT length mismatch '+r.summary+
        ' expected '+p.requested.toString());
    }
    if(p.command==8&&r.bodyLength!=32){
      throw FormatException('NU preparation response length mismatch');
    }
    if(p.command==4&&r.bodyLength>p.requested){
      throw FormatException('NU bulk IN returned too many bytes');
    }
    _pending.remove(r.sequence);
    return p;
  }
}
