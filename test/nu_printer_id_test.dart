import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_canon_connection.dart';

void main(){
  test('printer class GET_DEVICE_ID matches captured request',(){
    final p=NuCanonConnection.capturedPrinterIdRequest();
    expect(p.length,1460);
    expect(p.sublist(16,24),[85,78,84,36,0,8,2,0]);
    expect(p[24],0x18);
    expect(p.sublist(48,56),[0xa1,0,0,0,0,1,0xf1,3]);
  });
  test('validates Canon IEEE 1284 printer response',(){
    const content='MFG:Canon;CMD:IVEC;MDL:G2010 series;';
    final idBytes=content.codeUnits;
    final dataLength=idBytes.length+2;
    final r=Uint8List(40+dataLength);
    r.setAll(0,[85,78,84,36,0,dataLength+8,2,1,0x18]);
    r.setAll(32,[0xa1,0,0,0,0,1,0xf1,3]);
    r[40]=dataLength>>8;r[41]=dataLength&255;
    r.setAll(42,idBytes);
    expect(NuCanonConnection.parsePrinterIdReply(r),content);
    r[8]=0x19;
    expect(()=>NuCanonConnection.parsePrinterIdReply(r),throwsFormatException);
  });
}
