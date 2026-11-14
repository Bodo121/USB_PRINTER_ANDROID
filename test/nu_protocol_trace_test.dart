import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_protocol.dart';

Uint8List response(int requestType,int sequence,{
  required int requested, int responseBytes=0,
}) {
  final reply=Uint8List(32+responseBytes);
  reply.setAll(0,const <int>[85,78,84,36]);
  reply[4]=responseBytes>>8;
  reply[5]=responseBytes&255;
  reply[6]=2;
  reply[7]=requestType+1;
  reply[8]=sequence&255;
  reply[9]=(sequence>>8)&255;
  reply[20]=requestType==2?requested&255:responseBytes&255;
  reply[21]=(requestType==2?requested:responseBytes)>>8;
  reply[26]=0x80;
  reply[27]=sequence&255;
  return reply;
}

void main() {
  test('capture-shaped 50-message pipeline stays framed and matches reordered replies',(){
    // Known prefix from Windows: prep40 OUT41 IN42 IN43 IN44. Later
    // messages are synthetic continuation to exercise the parser; the
    // full original 50-record PCAP is not committed to this repository.
    final pending=NuPendingReplies();
    final recorded=<({int op,int seq,int count})>[];
    for(var seq=40;seq<90;seq++){
      final op=seq==40?8:seq==41?2:
        seq<45?4:seq.isEven?4:2;
      final count=op==8?64:op==2&&seq==41?383:1024;
      final frame=switch(op){
        8 => NuWire.prepare(sequence:seq),
        2 => NuWire.bulkOut(Uint8List(count),sequence:seq),
        4 => NuWire.bulkIn(sequence:seq,endpoint:0x82,
            requestedLength:count),
        _ => throw StateError('Impossible'),
      };
      expect(frame.length,1460);
      expect(frame.sublist(0,16),NuWire.preamble);
      expect(frame.sublist(16,20),const <int>[85,78,84,36]);
      expect(frame[23],op);
      expect(NuWire.txSequence(frame),seq);
      expect((frame[20]<<8)|frame[21],count);
      expect(frame[36]|(frame[37]<<8),count);
      pending.add(op,seq,count);
      recorded.add((op:op,seq:seq,count:count));
    }
    expect(recorded.length,50);
    // The observed prep acknowledgment was delayed; our matcher must
    // accept any order, including all later replies before the first.
    for(final r in recorded.reversed){
      final payloadLen=r.op==8?32:
          r.op==4?(r.seq==44?487:r.seq<44?0:970):0;
      final reply=NuReply.parse(response(r.op,r.seq,
        requested:r.count,responseBytes:payloadLen));
      final match=pending.accept(reply);
      expect(match.sequence,r.seq);
    }
    expect(pending.isEmpty,isTrue);
  });

  test('16-bit LE sequences are distinct even when low byte is identical',(){
    final p=NuPendingReplies();
    final hi=NuWire.bulkOut(Uint8List(1024),sequence:0x0129);
    final lo=NuWire.bulkOut(Uint8List(1024),sequence:0x0029);
    expect(NuWire.txSequence(hi),0x0129);
    expect(hi[24],lo[24]);
    expect(hi[25],1);
    p.add(2,0x0129,1024);
    p.add(2,0x0029,1024);
    p.accept(NuReply.parse(response(2,0x0029,requested:1024)));
    p.accept(NuReply.parse(response(2,0x0129,requested:1024)));
    expect(p.isEmpty,isTrue);
  });

  test('rejects wrong command, short OUT acknowledgment, and duplicates',(){
    final p=NuPendingReplies();
    p.add(2,43,1024);
    expect(()=>p.add(2,43,1024),throwsStateError);
    expect(()=>p.accept(NuReply.parse(
      response(4,43,requested:1024))),throwsFormatException);
    expect(()=>p.accept(NuReply.parse(
      response(2,43,requested:383))),throwsFormatException);
    expect(p.length,1);
    p.accept(NuReply.parse(response(2,43,requested:1024)));
    expect(p.isEmpty,isTrue);
  });

  test('OUT max 1412; no payload in IN; no repetition of raw buffers',(){
    expect(NuWire.bulkOut(Uint8List(1024),sequence:75).length,1460);
    expect(()=>NuWire.bulkOut(Uint8List(1413),sequence:75),
      throwsFormatException);
    expect(()=>NuWire.bulkOut(Uint8List(0),sequence:75),
      throwsFormatException);
    final read=NuWire.bulkIn(sequence:0x345,endpoint:0x82);
    expect(read.length,1460);
    expect(read.sublist(48).every((x)=>x==0),isTrue);
    expect(read[24],0x45);
    expect(read[25],0x03);
  });
}
