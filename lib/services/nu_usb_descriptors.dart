import 'dart:typed_data';

/// Read-only USB descriptor inspection of reassembled NU hub replies.
/// This class never opens a socket or issues a device-claim request.
class NuUsbDeviceDescriptor {
  const NuUsbDeviceDescriptor({
    required this.vendorId,required this.productId,
    required this.usbVersion,required this.deviceClass,
    required this.maxPacketSize0,required this.configurationCount,
    required this.offset,
  });
  final int vendorId;
  final int productId;
  final int usbVersion;
  final int deviceClass;
  final int maxPacketSize0;
  final int configurationCount;
  final int offset;
  String get vendorProductHex =>
      '${vendorId.toRadixString(16).padLeft(4,'0')}:' +
      productId.toRadixString(16).padLeft(4,'0');

  /// Search only for well-formed 18-byte USB DEVICE descriptors. A matching
  /// VID/PID is evidence of enumeration, not proof of USB ownership.
  static List<NuUsbDeviceDescriptor> find(Uint8List bytes) {
    final found=<NuUsbDeviceDescriptor>[];
    for(var i=0;i+18<=bytes.length;i++){
      if(bytes[i]!=18||bytes[i+1]!=1)continue;
      final usb=bytes[i+2]|(bytes[i+3]<<8);
      final mps=bytes[i+7];
      final count=bytes[i+17];
      if((usb&0xff00)==0||!<int>{8,16,32,64}.contains(mps)||
          count==0)continue;
      found.add(NuUsbDeviceDescriptor(
        vendorId:bytes[i+8]|(bytes[i+9]<<8),
        productId:bytes[i+10]|(bytes[i+11]<<8),
        usbVersion:usb,deviceClass:bytes[i+4],
        maxPacketSize0:mps,configurationCount:count,offset:i));
    }
    return found;
  }
}
