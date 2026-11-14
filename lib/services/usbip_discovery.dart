import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Read-only standard Linux USB/IP (TCP 3240) discovery.
/// The DIGITUS/NU V1.25 utility may use a PROPRIETARY protocol instead.
/// Never issue IMPORT, attach, device claim, or URB transfer commands.
class UsbIpDevice {
  const UsbIpDevice({
    required this.busId,
    required this.vendorId,
    required this.productId,
    required this.interfaceCount,
    required this.product,
    required this.manufacturer,
  });
  final String busId, product, manufacturer;
  final int vendorId, productId, interfaceCount;
  String get identity =>
      '${vendorId.toRadixString(16).padLeft(4,'0')}:' 
      '${productId.toRadixString(16).padLeft(4,'0')}';
}

class UsbIpResult {
  const UsbIpResult(this.supported,this.devices,this.detail);
  final bool supported;
  final List<UsbIpDevice> devices;
  final String detail;
}

/// A tiny RFC-documented USB/IP DEVLIST parser. Binary header:
/// version(2), opcode(2), status(4), count(4), then exported devices.
/// No mutable USB activity is performed by this probe.
class UsbIpDiscovery {
  const UsbIpDiscovery();

  static const int port = 3240;
  static const List<int> request = [0x01,0x11,0x80,0x05,0,0,0,0];

  static bool _privateIpv4(String host) {
    final p=InternetAddress.tryParse(host);
    if(p==null||p.type!=InternetAddressType.IPv4)return false;
    final a=p.rawAddress;
    return a[0]==10 || a[0]==192&&a[1]==168 ||
      a[0]==172&&a[1]>=16&&a[1]<=31;
  }

  static String _zeroString(Uint8List a,int start,int size) {
    final bytes=a.sublist(start,start+size);
    final zero=bytes.indexOf(0);
    return utf8.decode(zero>=0?bytes.sublist(0,zero):bytes,
        allowMalformed:true).trim();
  }

  static UsbIpResult parse(Uint8List data) {
    if(data.length<12)return const UsbIpResult(false,[],'Incomplete USB/IP header');
    final view=ByteData.sublistView(data);
    final version=view.getUint16(0,Endian.big);
    final op=view.getUint16(2,Endian.big);
    final status=view.getUint32(4,Endian.big);
    if(version!=0x0111||op!=0x0005) {
      return const UsbIpResult(false,[],'Not a USB/IP DEVLIST reply');
    }
    if(status!=0)return UsbIpResult(false,[],'USB/IP server status $status');
    final count=view.getUint32(8,Endian.big);
    if(count>16)return const UsbIpResult(false,[],'Unexpected USB/IP device count');
    final results=<UsbIpDevice>[];
    var offset=12;
    for(var i=0;i<count;i++){
      // usbip_usb_device: path 256, busid 32, then 8 u32s and 4 u8s = 312 bytes.
      if(offset+312>data.length) {
        return const UsbIpResult(false,[],'Incomplete USB/IP device record');
      }
      final busId=_zeroString(data,offset+256,32);
      final vendor=view.getUint16(offset+300,Endian.big);
      final product=view.getUint16(offset+302,Endian.big);
      final interfaceCount=data[offset+311];
      if(interfaceCount>32||offset+312+interfaceCount*4>data.length){
        return const UsbIpResult(false,[],'Invalid USB/IP interface records');
      }
      // The server does not return human-readable vendor/product strings;
      // don't invent them from the model name.
      results.add(UsbIpDevice(
        busId:busId,vendorId:vendor,productId:product,
        interfaceCount:interfaceCount,manufacturer:'',product:''));
      offset+=312+interfaceCount*4;
    }
    return UsbIpResult(true,results,'Standard USB/IP DEVLIST answered');
  }

  Future<UsbIpResult> probe(String host) async {
    if(!_privateIpv4(host)){
      return const UsbIpResult(false,[],'USB/IP probe limited to private IPv4');
    }
    Socket? socket;
    StreamSubscription<Uint8List>? subscription;
    try {
      socket=await Socket.connect(host,port,
          timeout:const Duration(milliseconds:900));
      final bytes=<int>[];
      final complete=Completer<void>();
      subscription=socket.listen((part){
        // Stop reading on a small cap; never stream arbitrary data indefinitely.
        bytes.addAll(part.take((8192-bytes.length)<part.length ? (8192-bytes.length) : part.length));
        if(bytes.length>=8192&&!complete.isCompleted)complete.complete();
      },onError:(Object e){
        if(!complete.isCompleted)complete.complete();
      },onDone:(){
        if(!complete.isCompleted)complete.complete();
      });
      socket.add(request);
      await socket.flush();
      // Legacy implementations may hold the socket open after a reply.
      await complete.future.timeout(const Duration(milliseconds:1100),
          onTimeout:(){});
      return parse(Uint8List.fromList(bytes));
    }catch(_){
      return const UsbIpResult(false,[],
        'No response from standard USB/IP TCP/3240; vendor protocol may differ');
    }finally {
      await subscription?.cancel();
      socket?.destroy();
    }
  }
}
