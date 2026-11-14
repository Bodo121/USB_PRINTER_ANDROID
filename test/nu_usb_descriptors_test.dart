import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_usb_descriptors.dart';

void main(){
  test('recognizes Canon 04a9:183a from a USB device descriptor',(){
    final bytes=Uint8List.fromList([
      0x55,0x4e,0x54,0x24,0,0,0,0,
      18,1,0x00,0x02,0,0,0,64,
      0xa9,0x04,0x3a,0x18,0,1,1,2,3,1
    ]);
    final devices=NuUsbDeviceDescriptor.find(bytes);
    expect(devices.length,1);
    expect(devices.single.vendorProductHex,'04a9:183a');
    expect(devices.single.maxPacketSize0,64);
    expect(devices.single.offset,8);
  });
  test('ignores truncated or invalid descriptors',(){
    expect(NuUsbDeviceDescriptor.find(Uint8List.fromList([18,1,0,2])),isEmpty);
    final invalid=Uint8List.fromList([
      18,1,0,2,0,0,0,7,0xa9,4,0x3a,0x18,0,1,1,2,3,1
    ]);
    expect(NuUsbDeviceDescriptor.find(invalid),isEmpty);
  });
}
