import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/vendor_usb_discovery.dart';

void main(){
  test('Recognizes observed UNT dollar packet without assuming meaning',(){
    final packet=Uint8List(1460);
    packet.setAll(0,NuPacketFingerprint.prefix);
    packet[24]=0x57;
    final fp=NuPacketFingerprint.inspect(packet);
    expect(fp.hasUntSignature,isTrue);
    expect(fp.length,1460);
    expect(fp.sequenceByte,0x57);
  });
  test('Does not recognize partial or unrelated messages',(){
    expect(NuPacketFingerprint.inspect(Uint8List.fromList([85,78,84,36]))
      .hasUntSignature,isFalse);
    expect(NuPacketFingerprint.inspect(Uint8List(1460))
      .hasUntSignature,isFalse);
  });
  test('Never probes public addresses',()async{
    await expectLater(const NuVendorProbe().observe('8.8.8.8'),
      throwsFormatException);
  });
}
