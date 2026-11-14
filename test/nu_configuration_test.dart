import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_configuration.dart';
import 'package:digitus_print/services/nu_canon_connection.dart';

void main(){
  final bytes=Uint8List.fromList([
    9,2,62,0,2,1,0,0xc0,1,
    9,4,0,0,3,0xff,0,0xff,0,
    7,5,7,2,0,2,0,
    7,5,0x88,2,0,2,0,
    7,5,0x89,3,64,0,11,
    9,4,1,0,2,7,1,2,0,
    7,5,1,2,0,2,0,
    7,5,0x82,2,0,2,0
  ]);
  test('Canon configuration has printer-class interface and bulk OUT 01',(){
    final config=NuConfigurationDecoder.decode(bytes);
    expect(config.totalLength,62);
    expect(config.interfaces.length,2);
    expect(config.interfaces[0].bulkOut!.address,7);
    expect(config.printerInterface!.number,1);
    expect(config.printerInterface!.bulkOut!.address,1);
    expect(config.printerInterface!.endpoints[1].address,0x82);
  });
  test('read-only captured configuration request carries 09/62 length',(){
    final a=NuCanonConnection.capturedConfigurationRequest(
      sequence:0x16,length:9);
    final b=NuCanonConnection.capturedConfigurationRequest(
      sequence:0x17,length:62);
    expect(a.length,1460);
    expect(a[24],0x16);expect(a[34],2);expect(a[54],9);
    expect(b[24],0x17);expect(b[34],2);expect(b[54],62);
  });
  test('configuration reply matches transaction sequence and USB setup',(){
    final r=Uint8List(102);
    r.setAll(0,[0x55,0x4e,0x54,0x24,0,70,2,1,0x17]);
    r.setAll(32,[0x80,0x06,0,2,0,0,62,0]);
    r.setAll(40,bytes);
    final payload=NuCanonConnection.configurationReplyPayload(r,
      sequence:0x17,expectedLength:62);
    expect(payload,bytes);
    expect(NuCanonConnection.configurationReplyPayload(r,
      sequence:0x16,expectedLength:62),isNull);
  });
  test('rejects truncated USB configuration',(){
    expect(()=>NuConfigurationDecoder.decode(bytes.sublist(0,61)),
      throwsFormatException);
  });
}
