import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'usb_port_diagnostics.dart';

/// DA-70251 NU-series DCP$ requests from the owner's 2026-11-14
/// Wireshark capture. This is device discovery, not a device claim.
///
/// Observed client: 40 bytes, local UDP 52340 -> hub UDP 52330.
/// Observed reply: 1059 bytes, hub UDP 52330 -> local UDP 52340.
/// Reply echoes bytes 8..11 of the client's request.
class DcpHubInfo {
  const DcpHubInfo({
    required this.ip, required this.mac, required this.name,
    required this.physicalPortCount, required this.reportedDevice,
    required this.manufacturer, required this.serial,
    this.vendorId, this.productId,
  });
  final String ip, mac, name;
  final int physicalPortCount;
  final String? reportedDevice, manufacturer, serial;
  final int? vendorId, productId;
}

class DcpPacket {
  static String _str(Uint8List data, int offset, int count) {
    if(offset<0||offset+count>data.length)return '';
    final segment=data.sublist(offset,offset+count);
    final end=segment.indexOf(0);
    return ascii.decode(end<0?segment:segment.sublist(0,end),
      allowInvalid:true).trim();
  }

  static Uint8List request({required int localPort, required int nonce}) {
    if(localPort<1||localPort>65535||nonce<0||nonce>65535) {
      throw const FormatException('Invalid DCP source port or sequence');
    }
    final packet=Uint8List(40);
    packet.setAll(0,ascii.encode(String.fromCharCodes(const [68,67,80,36])));
    // Captured code 0x0000000D, big endian.
    packet[7]=0x0d;
    packet[8]=nonce>>8;
    packet[9]=nonce&255;
    packet[12]=localPort>>8;
    packet[13]=localPort&255;
    packet[14]=2;
    return packet;
  }

  static DcpHubInfo? parse(Uint8List bytes,String sourceIp,{int? nonce}) {
    if(bytes.length<288 || bytes.length>4096 ||
       !UsbPortDiagnostics.privateIpv4(sourceIp))return null;
    if(_str(bytes,0,4)!=String.fromCharCodes(const [68,67,80,36]) ||
       _str(bytes,104,4)!=String.fromCharCodes(const [69,83,84,36]))return null;
    if(nonce!=null && (bytes[8]!=(nonce>>8)||bytes[9]!=(nonce&255)))return null;
    final sockets=bytes[32], name=_str(bytes,40,64);
    if(sockets<1||sockets>16||!name.contains('USB')||
       bytes.sublist(114,118).join('.')!=sourceIp)return null;
    final mac=bytes.sublist(16,22)
      .map((b)=>b.toRadixString(16).padLeft(2,'0')).join(':').toUpperCase();
    String? device,manufacturer,serial;
    if(_str(bytes,176,4)==String.fromCharCodes(const [68,67,80,36])){
      device=_str(bytes,200,32);
      manufacturer=_str(bytes,232,40);
      serial=_str(bytes,272,16);
    }
    // The exact DCP vendor/product-ID fields are not fully mapped yet.
    // Do not promote a USB VID/PID inferred from a nested record to fact.
    return DcpHubInfo(
      ip:sourceIp,mac:mac,name:name,physicalPortCount:sockets,
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

  /// Sends *only* the 40-byte discovery message observed on the wire.
  /// No TCP connection, USB claim, USB configuration, or raster is sent.
  Future<DcpListenResult> discover({
    required String expectedHub,
    Duration duration=const Duration(seconds:4),
  }) async {
    if(!UsbPortDiagnostics.privateIpv4(expectedHub)) {
      throw const FormatException('DCP discovery is restricted to private IPv4');
    }
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    final done=Completer<DcpHubInfo?>();
    final nonce=Random.secure().nextInt(65536);
    try {
      // Prefer the real Windows source port; fall back when already occupied.
      try {
        socket=await RawDatagramSocket.bind(InternetAddress.anyIPv4,52340);
      } on SocketException {
        socket=await RawDatagramSocket.bind(InternetAddress.anyIPv4,0);
      }
      final bound=socket!;
      subscription=bound.listen((event) {
        if(event!=RawSocketEvent.read)return;
        Datagram? datagram;
        while((datagram=bound.receive())!=null) {
          final entry=datagram!;
          if(entry.address.address!=expectedHub ||
             entry.port!=52330)continue;
          final result=DcpPacket.parse(Uint8List.fromList(entry.data),
             expectedHub,nonce:nonce);
          if(result!=null&&!done.isCompleted)done.complete(result);
        }
      },onError:(Object e) {
        if(!done.isCompleted)done.completeError(e);
      });
      final query=DcpPacket.request(localPort:bound.port,nonce:nonce);
      final sent=bound.send(query,InternetAddress(expectedHub),52330);
      if(sent!=query.length)throw const SocketException(
        'Unable to transmit the complete DCP discovery request');
      final info=await done.future.timeout(duration,onTimeout:()=>null);
      return DcpListenResult(info,info==null
        ? 'Sent DCP discovery to UDP 52330 but received no matching reply '
          'on local port ${bound.port}. Check hub connectivity and disconnect '
          'the Windows USB Server client before retrying.'
        : 'Active DCP discovery succeeded: ${info.name}, '
          '${info.physicalPortCount} USB sockets, MAC ${info.mac}. '
          'USB attachment and printing remain unverified.');
    } on SocketException catch(e){
      return DcpListenResult(null,'UDP discovery socket error: $e');
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
  }

  /// Legacy passive listening mode retained for debugging broadcasts.
  Future<DcpListenResult> listen({
    required String expectedHub,
    Duration duration=const Duration(seconds:5),
  }) async {
    if(!UsbPortDiagnostics.privateIpv4(expectedHub)){
      throw const FormatException('DCP listening requires private IPv4');
    }
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    final done=Completer<DcpHubInfo?>();
    try {
      socket=await RawDatagramSocket.bind(InternetAddress.anyIPv4,52340,
        reuseAddress:true);
      final bound=socket!;
      subscription=bound.listen((event){
        if(event!=RawSocketEvent.read)return;
        Datagram? datagram;
        while((datagram=bound.receive())!=null) {
          final entry=datagram!;
          if(entry.address.address!=expectedHub)continue;
          final info=DcpPacket.parse(Uint8List.fromList(entry.data),expectedHub);
          if(info!=null&&!done.isCompleted)done.complete(info);
        }
      });
      final info=await done.future.timeout(duration,onTimeout:()=>null);
      return DcpListenResult(info,info==null
        ? 'No unsolicited DCP announcement. Try active discovery instead.'
        : 'Passive DCP response: ${info.name}');
    }finally {
      await subscription?.cancel();
      socket?.close();
    }
  }
}
