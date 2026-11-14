import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_bulk_decoder.dart';

void main(){
  test('captured printer bulk OUT request and 02/03 completion correlate',(){
    final sent=Uint8List(1460);
    sent.setAll(0,List<int>.generate(16,(i)=>16-i));
    sent.setAll(16,[85,78,84,36,1,0x7f,2,2,0x29,0,0,0,0,0,1,0,
      1,0,0x30,0xf0,0x7f,1]);
    final request=NuBulkDecoder.request(sent)!;
    expect(request.isOut,isTrue);
    expect(request.endpoint,1);
    expect(request.requestedLength,383);
    final received=Uint8List(32);
    received.setAll(0,[85,78,84,36,0,0,2,3,0x29,0,0,0,0,0,1,1,
      8,2,0x32,0xff,0x7f,1]);
    received[26]=0x80;
    received[27]=0x29;
    final ack=NuBulkDecoder.completion(received)!;
    expect(NuBulkDecoder.correlates(request,ack),isTrue);
    received[8]=0x2a;
    received[27]=0x2a;
    expect(NuBulkDecoder.correlates(request,
      NuBulkDecoder.completion(received)!),isFalse);
  });
  test('recognizes captured bulk IN poll without calling it print data',(){
    final sent=Uint8List(1460);
    sent.setAll(0,List<int>.generate(16,(i)=>16-i));
    sent.setAll(16,[85,78,84,36,4,0,2,2,0x30,0,0,0,0,0,1,0,
      0x81,0,0x30,0xf0,0,4]);
    final request=NuBulkDecoder.request(sent)!;
    expect(request.isIn,isTrue);
    expect(request.requestedLength,1024);
  });
}
