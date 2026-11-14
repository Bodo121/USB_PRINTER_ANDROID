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
    if(bytes.length<176 || bytes.length>4096) return null;
    if(_str(bytes,0,4)!='DCP$' || _str(bytes,104,4)!='EST$')return null;
    if(!UsbPortDiagnostics.privateIpv4(sourceIp))return null;
    final mac=_mac(bytes,16),name=_str(bytes,40,64);
    final sockets=bytes[32];
    final embeddedIp=_ip(bytes,114);
    if(sockets<1 || sockets>16 || name.isEmpty ||
      !name.contains('USB') || embeddedIp!=sourceIp)return null;
    String? device,manufacturer,serial;
    if(bytes.length>=288 && _str(bytes,176,4)=='DCP$'){
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
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    final completed=Completer<DcpHubInfo?>();
    try{
      socket=await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,52340,reuseAddress:true);
      socket.broadcastEnabled=true;
      subscription=socket.listen((event){
        if(event!=RawSocketEvent.read)return;
        Datagram? datagram;
        while((datagram=socket!.receive())!=null){
          final d=datagram!;
          if(d.address.address!=expectedHub)continue;
          final info=DcpPacket.parse(Uint8List.fromList(d.data),expectedHub);
          if(info!=null&&!completed.isCompleted)completed.complete(info);
        }
      },onError:(Object e){
        if(!completed.isCompleted)completed.completeError(e);
      });
      final info=await completed.future.timeout(duration,onTimeout:()=>null);
      return DcpListenResult(info,info==null
        ? 'No DCP$ advertisement observed on UDP 52340. The hub may be quiet, '
          'broadcasts may be blocked on Wi-Fi, or another application may own '
          'the port. This does not prove the hub is offline.'
        : 'Observed DCP$ USB server announcement from ${info.ip}: '
          '${info.physicalPortCount} physical USB sockets.');
    }on SocketException catch(e){
      return DcpListenResult(null,'Could not listen on UDP 52340: $e');
    }finally{
      await subscription?.cancel();
      socket?.close();
    }
  }
}
