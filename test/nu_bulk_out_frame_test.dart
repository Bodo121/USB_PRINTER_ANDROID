import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_canon_connection.dart';
void main(){
  test('383-byte NU bulk OUT header equals captured Windows 02/02 packet',(){
    final raw=Uint8List.fromList(List.generate(383,(i)=>i&255));
    final frame=NuCanonConnection.capturedBulkOutFrame(raw,sequence:0x29);
    expect(frame.length,1460);
    expect(frame.sublist(0,48),<int>[
      16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,
      0x55,0x4e,0x54,0x24,0x01,0x7f,0x02,0x02,
      0x29,0,0,0,0,0,1,0,
      1,0,0x30,0xf0,0x7f,0x01,0,0,
      0,0,0x80,0x29,0,0x12,0x72,0x20
    ]);
    expect(frame.sublist(48,431),raw);
    expect(frame.sublist(431).every((b)=>b==0),isTrue);
  });
  test('last small chunk updates both NU length fields and raw data',(){
    final frame=NuCanonConnection.capturedBulkOutFrame(
      Uint8List.fromList([0x1b,0x40,0x00,0x0a]),sequence:0x2a);
    expect(frame.sublist(20,24),[0,4,2,2]);
    expect(frame.sublist(36,38),[4,0]);
    expect(frame[43],0x2a);
    expect(frame.sublist(48,52),[0x1b,0x40,0,0x0a]);
    expect(frame[52],0);
  });
  test('rejects unsafe sizes',(){
    expect(()=>NuCanonConnection.capturedBulkOutFrame(
      Uint8List(384),sequence:0x29),throwsFormatException);
    expect(()=>NuCanonConnection.capturedBulkOutFrame(
      Uint8List(0),sequence:0x29),throwsFormatException);
  });
}
