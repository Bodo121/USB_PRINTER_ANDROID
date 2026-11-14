import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_canon_connection.dart';
void main(){
  test('captured 02/03 bulk completion matches transfer 0x29',(){
    final response=Uint8List.fromList(<int>[
      85,78,84,36,0,0,2,3,0x29,0,0,0,0,0,1,1,
      0x08,0x02,0x32,0xff,0x7f,0x01,0xe5,0x17,
      0,0,0x80,0x29,0,0x12,0x72,0x22
    ]);
    expect(NuCanonConnection.isBulkOutCompletion(response,
      sequence:0x29,count:383),isTrue);
    expect(NuCanonConnection.isBulkOutCompletion(response,
      sequence:0x2a,count:383),isFalse);
    expect(NuCanonConnection.isBulkOutCompletion(response,
      sequence:0x29,count:382),isFalse);
  });
  test('delayed preparation 02/09 is a separate response frame',(){
    final response=Uint8List(64);
    response.setAll(0,<int>[85,78,84,36,0,32,2,9,0x28]);
    expect(NuCanonConnection.isBulkPreparationResponse(response),isTrue);
    expect(NuCanonConnection.isBulkOutCompletion(response,
      sequence:0x29,count:383),isFalse);
  });

  test('NU 02/08 setup is 1460 bytes; validates 02/09 reply',(){
    final request=NuCanonConnection.capturedBulkPreparationRequest();
    expect(request.length,1460);
    expect(request.sublist(16,48),[85,78,84,36,0,64,2,8,
      0x28,0,0,0,0,0,1,0,1,0,0x0b,0,64,0,0,0,
      4,0xf8,0x80,0x28,0x40,0x10,0x92,0x34]);
    final reply=Uint8List(64);
    reply.setAll(0,[85,78,84,36,0,32,2,9,0x28]);
    expect(NuCanonConnection.isBulkPreparationResponse(reply),isTrue);
    reply[7]=3;
    expect(NuCanonConnection.isBulkPreparationResponse(reply),isFalse);
  });
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
      Uint8List(1413),sequence:0x29),throwsFormatException);
    expect(()=>NuCanonConnection.capturedBulkOutFrame(
      Uint8List(0),sequence:0x29),throwsFormatException);
  });
}
