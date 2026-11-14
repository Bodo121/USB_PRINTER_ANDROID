import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/usbip_discovery.dart';

void main(){
  test('standard USB/IP request format',(){
    expect(UsbIpDiscovery.request,[1,17,128,5,0,0,0,0]);
  });
  test('parse standard DEVLIST empty response',(){
    final response=Uint8List.fromList([1,17,0,5,0,0,0,0,0,0,0,0]);
    final parsed=UsbIpDiscovery.parse(response);
    expect(parsed.supported,true);
    expect(parsed.devices,isEmpty);
  });
  test('reject arbitrary proprietary response',(){
    final parsed=UsbIpDiscovery.parse(
      Uint8List.fromList(List<int>.filled(12,0)));
    expect(parsed.supported,false);
  });
  test('parse one exported device record',(){
    final data=Uint8List(12+312+4);
    data.setAll(0,[1,17,0,5,0,0,0,0,0,0,0,1]);
    data.setAll(12+256,'1-1'.codeUnits);
    // USB vendor ID 0x04a9 = Canon, product ID is arbitrary test fixture.
    data.setAll(12+300,[0x04,0xa9,0x12,0x34]);
    data[12+311]=1;
    final parsed=UsbIpDiscovery.parse(data);
    expect(parsed.supported,true);
    expect(parsed.devices.single.identity,'04a9:1234');
    expect(parsed.devices.single.busId,'1-1');
  });
}
