import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/dcp_discovery.dart';

void main(){
  test('Decodes DCP hub identity from observed 1059-byte reply',(){
    final d=Uint8List(1059);
    d.setAll(0,'DCP\$'.codeUnits);
    d.setAll(16,[0x00,0x24,0x9b,0x07,0x67,0xdd]);
    d[32]=4;
    d.setAll(40,'IP USB Sharing Station-0767DD'.codeUnits);
    d.setAll(104,'EST\$'.codeUnits);
    d.setAll(114,[192,168,0,74]);
    d.setAll(176,'DCP\$'.codeUnits);
    d.setAll(200,'G2010 series'.codeUnits);
    d.setAll(232,'Canon'.codeUnits);
    d.setAll(272,'019249'.codeUnits);
    final parsed=DcpPacket.parse(d,'192.168.0.74');
    expect(parsed,isNotNull);
    expect(parsed!.name,'IP USB Sharing Station-0767DD');
    expect(parsed.mac,'00:24:9B:07:67:DD');
    expect(parsed.physicalPortCount,4);
    expect(parsed.reportedDevice,'G2010 series');
    expect(parsed.manufacturer,'Canon');
    expect(parsed.serial,'019249');
  });
  test('Rejects public network and invalid DCP framing',(){
    final d=Uint8List(1059);
    expect(DcpPacket.parse(d,'192.168.0.74'),isNull);
    d.setAll(0,'DCP\$'.codeUnits);
    expect(DcpPacket.parse(d,'8.8.8.8'),isNull);
  });
}
