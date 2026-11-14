import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'usb_port_diagnostics.dart';

/// Observed legacy NU V1.25 packet, not a complete USB-over-IP specification.
/// The user's Windows capture saw this client-side prefix on TCP 4660.
/// It does NOT authorize replaying the packet to a printer hub.
class NuPacketFingerprint {
  const NuPacketFingerprint(this.hasUntSignature, this.length, this.sequenceByte);
  final bool hasUntSignature;
  final int length;
  final int? sequenceByte;

  static const prefix = <int>[
    16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,85,78,84,36,
  ];

  static NuPacketFingerprint inspect(Uint8List packet) {
    final match=packet.length>=prefix.length &&
        List.generate(prefix.length,(i)=>packet[i]==prefix[i]).every((x)=>x);
    return NuPacketFingerprint(
      match,packet.length, match && packet.length>24?packet[24]:null);
  }
}

/// A deliberately passive vendor service observation.
/// A TCP connection and incoming banner are recorded but NO handshake,
/// attachment request, device selection, USB control or bulk I/O is sent.
/// This prevents guessing a vendor opcode or disturbing an occupied USB port.
class NuVendorObservation {
  const NuVendorObservation({
    required this.connected,
    required this.receivedBytes,
    required this.fingerprintFound,
    required this.detail,
  });
  final bool connected;
  final int receivedBytes;
  final bool fingerprintFound;
  final String detail;
}

class NuVendorProbe {
  const NuVendorProbe();

  Future<NuVendorObservation> observe(String host) async {
    if(!UsbPortDiagnostics.privateIpv4(host)){
      throw const FormatException('NU probe requires a private LAN IPv4 host');
    }
    Socket? socket;
    StreamSubscription<Uint8List>? listener;
    var received=0;
    var signature=false;
    try {
      socket=await Socket.connect(host,4660,
          timeout:const Duration(milliseconds:1100));
      final done=Completer<void>();
      // Capture at most 2048 bytes, without retaining private payloads.
      listener=socket.listen((bytes) {
        if(received<2048){
          received+=(2048-received)<bytes.length?(2048-received):bytes.length;
          if(NuPacketFingerprint.inspect(bytes).hasUntSignature)signature=true;
        }
        if(received>=2048&&!done.isCompleted)done.complete();
      },onError:(Object e){
        if(!done.isCompleted)done.complete();
      },onDone:(){
        if(!done.isCompleted)done.complete();
      });
      await done.future.timeout(const Duration(milliseconds:700),
          onTimeout:(){});
      return NuVendorObservation(
        connected:true,receivedBytes:received,
        fingerprintFound:signature,
        detail:received==0
          ? 'TCP 4660 accepts a connection but sends no unsolicited greeting. '
            'This matches a protocol requiring an unknown client handshake; '
            'no vendor commands were sent.'
          : 'TCP 4660 returned $received bytes unsolicited. '
            'No USB session was established or device claimed.');
    }on SocketException catch(e){
      return NuVendorObservation(
        connected:false,receivedBytes:0,fingerprintFound:false,
        detail:'No TCP 4660 connection: ${e.osError?.message??e.message}');
    }on TimeoutException {
      return const NuVendorObservation(
        connected:false,receivedBytes:0,fingerprintFound:false,
        detail:'TCP 4660 connection timed out');
    }finally {
      await listener?.cancel();
      socket?.destroy();
    }
  }
}
