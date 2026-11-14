import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_canon_connection.dart';
void main(){
  test('Captured first control request uses 1460-byte framing',(){
    final b=NuCanonConnection.capturedDeviceDescriptorRequest();
    expect(b.length,1460);
    expect(b.sublist(0,16),List<int>.generate(16,(i)=>16-i));
    expect(b.sublist(16,24),[0x55,0x4e,0x54,0x24,0,8,2,0]);
    expect(b.sublist(48,56),[0x80,0x06,0,1,0,0,18,0]);
    expect(b[1459],255);
  });
  test('Verified reply must contain Canon 04a9:183a',(){
    final r=Uint8List(58);
    r.setAll(0,[0x55,0x4e,0x54,0x24,0,0x1a,2,1,0x15]);
    r.setAll(32,[0x80,0x06,0,1,0,0,18,0]);
    r.setAll(40,[18,1,0,2,0,0,0,64,0xa9,4,0x3a,0x18,2,1,1,2,3,1]);
    expect(NuCanonConnection.verifiesCanon(r),isTrue);
    r[50]=0xff;
    expect(NuCanonConnection.verifiesCanon(r),isFalse);
  });
}
