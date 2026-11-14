import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_session.dart';

void main(){
  test('NU handshake matches 116-byte client capture structure',(){
    final bytes=NuHello.make('192.168.0.117',clientName:'WIN-K74BQQ33NSG');
    expect(bytes.length,116);
    expect(bytes.sublist(0,16),NuHello.prefix);
    expect(bytes.sublist(16,28),<int>[
      85,78,84,36,0,68,2,10,20,0,128,0]);
    expect(bytes[32],2);
    expect(bytes.sublist(48,63),'WIN-K74BQQ33NSG'.codeUnits);
    expect(bytes.sublist(112,116),<int>[192,168,0,117]);
  });
  test('Parses captured 100-byte hub session greeting',(){
    final reply=Uint8List(100);
    reply.setAll(0,<int>[85,78,84,36,0,68,0,11,20,0,128,0]);
    reply.setAll(32,'WIN-K74BQQ33NSG'.codeUnits);
    reply.setAll(96,<int>[192,168,0,117]);
    expect(NuHello.isGreetingReply(reply),isTrue);
    expect(NuHello.responseName(reply),'WIN-K74BQQ33NSG');
    reply[7]=10;
    expect(NuHello.isGreetingReply(reply),isFalse);
  });
}
