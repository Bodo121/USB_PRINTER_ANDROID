import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/dcp_discovery.dart';

void main(){
  test('DCP query matches Windows capture except nonce',(){
    final query=DcpPacket.request(localPort:52340,nonce:0x62b9);
    expect(query.length,40);
    expect(query.sublist(0,16),<int>[
      68,67,80,36,0,0,0,13,0x62,0xb9,0,0,0xcc,0x74,2,0]);
    expect(query.sublist(16).every((v)=>v==0),isTrue);
  });
  test('Parse 1059-byte hub reply and require matched nonce',(){
    final raw=Uint8List(1059);
    raw.setAll(0,[68,67,80,36]);
    raw[8]=0x62;raw[9]=0xb9;
    raw.setAll(16,[0x00,0x24,0x9b,0x07,0x67,0xdd]);
    raw[32]=4;
    raw.setAll(40,'IP USB Sharing Station-0767DD'.codeUnits);
    raw.setAll(104,[69,83,84,36]);
    raw.setAll(114,[192,168,0,74]);
    raw.setAll(176,[68,67,80,36]);
    raw.setAll(200,'G2010 series'.codeUnits);
    raw.setAll(232,'Canon'.codeUnits);
    raw.setAll(272,'019249'.codeUnits);
    final info=DcpPacket.parse(raw,'192.168.0.74',nonce:0x62b9);
    expect(info,isNotNull);
    expect(info!.mac,'00:24:9B:07:67:DD');
    expect(info.name,'IP USB Sharing Station-0767DD');
    expect(info.physicalPortCount,4);
    expect(info.reportedDevice,'G2010 series');
    expect(info.manufacturer,'Canon');
    expect(info.serial,'019249');
    expect(DcpPacket.parse(raw,'192.168.0.74',nonce:0x0203),isNull);
    expect(DcpPacket.parse(raw,'8.8.8.8'),isNull);
  });
}
