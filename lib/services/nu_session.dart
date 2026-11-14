import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'usb_port_diagnostics.dart';

/// Only the initial NU V1.25 TCP greeting is understood well enough to try.
/// Derived from plm222.pcapng, where a 116-byte Windows request elicited
/// a 100-byte hub reply on TCP 4660. This is NOT USB attachment or printing.
class NuHello {
  static const prefix=<int>[16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1];
  static Uint8List make(String clientIpv4,{String clientName='DigitusPrint'}) {
    if(!UsbPortDiagnostics.privateIpv4(clientIpv4)) {
      throw const FormatException('Client IP must be a private IPv4 address');
    }
    if(clientName.isEmpty || clientName.length>63 ||
       !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(clientName)){
      throw const FormatException('Invalid client name');
    }
    final packet=Uint8List(116);
    packet.setAll(0,prefix);
    packet.setAll(16,const [85,78,84,36,0,68,2,10,20,0,128,0]);
    packet[32]=2;
    packet.setAll(48,clientName.codeUnits);
    packet.setAll(112,clientIpv4.split('.').map(int.parse));
    return packet;
  }

  static bool isGreetingReply(Uint8List bytes) =>
      bytes.length==100 &&
      bytes[0]==85 && bytes[1]==78 && bytes[2]==84 && bytes[3]==36 &&
      bytes[4]==0 && bytes[5]==68 && bytes[6]==0 && bytes[7]==11;

  static String? responseName(Uint8List bytes){
    if(!isGreetingReply(bytes))return null;
    final field=bytes.sublist(32,96);
    final end=field.indexOf(0);
    return String.fromCharCodes(end<0?field:field.sublist(0,end));
  }
}

class NuHelloResult {
  const NuHelloResult({required this.accepted,required this.detail});
  final bool accepted;
  final String detail;
}

class NuSessionDiagnostics {
  const NuSessionDiagnostics();

  /// The user must initiate this test; no USB requests follow the greeting.
  Future<NuHelloResult> greeting(String host) async {
    if(!UsbPortDiagnostics.privateIpv4(host)){
      throw const FormatException('Hub must have a private IPv4 address');
    }
    Socket? socket;
    StreamSubscription<Uint8List>? subscription;
    final response=BytesBuilder(copy:false);
    final received=Completer<Uint8List?>();
    try {
      socket=await Socket.connect(host,4660,
          timeout:const Duration(seconds:3));
      socket.setOption(SocketOption.tcpNoDelay,true);
      subscription=socket.listen((chunk){
        if(received.isCompleted)return;
        if(response.length+chunk.length>256){
          received.complete(null);
          return;
        }
        response.add(chunk);
        if(response.length>=100) {
          received.complete(response.takeBytes());
        }
      },onError:(Object e){
        if(!received.isCompleted)received.complete(null);
      },onDone:(){
        if(!received.isCompleted)received.complete(null);
      });
      final parts=host.split('.');
      final interfaces=await NetworkInterface.list(
        type:InternetAddressType.IPv4,includeLoopback:false);
      final addresses=interfaces.expand((i)=>i.addresses)
        .map((a)=>a.address)
        .where(UsbPortDiagnostics.privateIpv4).toList();
      final local=addresses.where((a){
        final p=a.split('.');
        return p[0]==parts[0]&&p[1]==parts[1]&&p[2]==parts[2];
      }).firstOrNull;
      if(local==null){
        return const NuHelloResult(accepted:false,
          detail:'No local Wi-Fi IPv4 address in the hub subnet; '
            'cannot form the observed handshake safely.');
      }
      socket.add(NuHello.make(local));
      await socket.flush();
      final reply=await received.future.timeout(const Duration(seconds:4),
          onTimeout:()=>null);
      if(reply==null||!NuHello.isGreetingReply(reply)){
        return NuHelloResult(accepted:false,
          detail:'No valid 100-byte UNT$ session greeting was received. '
            'No device was claimed and no USB transfer was sent.');
      }
      return NuHelloResult(accepted:true,
        detail:'Hub acknowledged the observed UNT$ session greeting. '
          'Echo name: ${NuHello.responseName(reply)}. '
          'This proves only the initial handshake, not USB attachment or printing.');
    }on SocketException catch(e) {
      return NuHelloResult(accepted:false,detail:'TCP 4660 error: $e');
    }finally {
      await subscription?.cancel();
      socket?.destroy();
    }
  }
}
