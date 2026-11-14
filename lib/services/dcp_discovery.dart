import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'usb_port_diagnostics.dart';

/// Passive decoder for the DA-70251's observed DCP$ UDP announcements.
/// Derived from the owner's actual NU V1.25 Windows capture, not KCodes NetUSB.
/// No device-claim, configuration, or print commands are transmitted.
class DcpHubInfo {
  const DcpHubInfo({
    required this.ip,
    required this.mac,
    required this.name,
    required this.physicalPortCount,
    required this.reportedDevice,
    required this.manufacturer,
    required this.serial,
  });
  final String ip, mac, name;
  final int physicalPortCount;
  final String? reportedDevice, manufacturer, serial;
}

class DcpPacket {
  static String _str(Uint8List data,int offset,int size) {
    if(offset<0 || offset+size>data.length)return '';
    final segment=data.sublist(offset,offset+size);
    final end=segment.indexOf(0);
    return ascii.decode(end<0?segment:segment.sublist(0,end),
      allowInvalid:true).trim();
  }
  static String _ip(Uint8List a,int offset) =>
      a.sublist(offset,offset+4).join('.');
  static String _mac(Uint8List a,int offset) =>
      a.sublist(offset,offset+6).map((v)=>v.toRadixString(16).padLeft(2,'0'))
        .join(':').toUpperCase();

  static DcpHubInfo? parse(Uint8List bytes,String sourceIp) {
    // 1059-byte DCP$ response in owner's PCAP:
    // bytes 16..21 = MAC, 32 = number of physical sockets, 40 = name,
    // EST$ at 104, with IP at 114; nested per-device DCP$ at offset 176.
    if(bytes.length<104 || bytes.length>4096) return null;
    if(_str(bytes,0,4)!='DCP$')return null;
    if(!UsbPortDiagnostics.privateIpv4(sourceIp))return null;
    final mac=_mac(bytes,16);
    final detailed=bytes.length>=176 && _str(bytes,104,4)=='EST$';
    final name=detailed?_str(bytes,40,64):'DA-70251 USB sharing server';
    final sockets=bytes[32];
    final embeddedIp=detailed?_ip(bytes,114):_ip(bytes,48);
    if(sockets<1 || sockets>16 || name.isEmpty || embeddedIp!=sourceIp)return null;
    String? device,manufacturer,serial;
    if(detailed && bytes.length>=288 && _str(bytes,176,4)=='DCP$'){
      device=_str(bytes,200,32);
      manufacturer=_str(bytes,232,40);
      serial=_str(bytes,272,16);
    }
    return DcpHubInfo(
      ip:sourceIp, mac:mac,name:name,physicalPortCount:sockets,
      reportedDevice:device?.isEmpty==true?null:device,
      manufacturer:manufacturer?.isEmpty==true?null:manufacturer,
      serial:serial?.isEmpty==true?null:serial);
  }
}

class DcpListenResult {
  const DcpListenResult(this.info,this.detail);
  final DcpHubInfo? info;
  final String detail;
}

class DcpDiscovery {
  const DcpDiscovery();

  /// The hub broadcast to PC UDP port 52340 in user's capture.
  /// Listen only. Binding can fail when the phone or another app owns port.
  Future<DcpListenResult> listen({
    required String expectedHub,
    Duration duration=const Duration(seconds:6),
  }) async {
    if(!UsbPortDiagnostics.privateIpv4(expectedHub)) {
      throw const FormatException('DCP listening requires a private hub IPv4');
    }
    final sockets=<RawDatagramSocket>[];
    final listeners=<StreamSubscription<RawSocketEvent>>[];
    DcpHubInfo? best;
    final done=Completer<void>();
    final errors=<String>[];
    try {
      for (final port in const [52340,52330]) {
        try {
          final socket=await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,port,reuseAddress:true);
          sockets.add(socket);
          listeners.add(socket.listen((event){
            if (event!=RawSocketEvent.read)return;
            Datagram? d;
            while ((d=socket.receive())!=null) {
              final packet=d!;
              if(packet.address.address!=expectedHub)continue;
              final info=DcpPacket.parse(
                Uint8List.fromList(packet.data),expectedHub);
              if(info==null)continue;
              if(best==null || info.reportedDevice!=null)best=info;
              if(info.reportedDevice!=null && !done.isCompleted){
                done.complete();
              }
            }
          },onError:(Object error){errors.add('$port: $error');}));
        } on SocketException catch(e) {
          errors.add('$port: $e');
        }
      }
      if (sockets.isEmpty) {
        return DcpListenResult(null,
          'Cannot bind DCP discovery listener: ${errors.join('; ')}');
      }
      await done.future.timeout(duration,onTimeout:(){});
      final info=best;
      return DcpListenResult(info,info==null
        ? 'No DCP$ advertisement observed on UDP 52330/52340. '
          'The hub may be quiet or Wi-Fi broadcast isolation may be enabled.'
        : info.reportedDevice!=null
          ? 'DA-70251 detailed device list received.'
          : 'DA-70251 broadcast received: ${info.physicalPortCount} USB ports. '
            'A full device list needs the vendor discovery request.');
    } finally {
      for (final listener in listeners) { await listener.cancel(); }
      for (final socket in sockets) { socket.close(); }
    }
  }
}
