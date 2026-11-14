import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'nu_session.dart';
import 'usb_port_diagnostics.dart';

/// Experimental DA-70251 transport: captured NU greeting followed by a
/// *read-only* USB GET_DESCRIPTOR control request. Successful enumeration
/// demonstrates the vendor USB path, not exclusive ownership of the device.
/// No print payload is ever sent by this class.
class NuCanonConnection {
  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  final _incoming=BytesBuilder(copy:false);
  Completer<void>? _signal;
  bool _ended=false;
  String? _connectedHost;

  bool get isConnected => _socket!=null && !_ended &&
      _connectedHost!=null;

  void _receive(Uint8List chunk) {
    _incoming.add(chunk);
    if(_signal!=null && !_signal!.isCompleted)_signal!.complete();
  }

  Future<Uint8List> _readExact(int length, Duration timeout) async {
    final deadline=DateTime.now().add(timeout);
    while(_incoming.length<length) {
      if(_ended)throw const SocketException('NU connection closed by hub');
      if(DateTime.now().isAfter(deadline)){
        throw TimeoutException('Timed out reading NU response ($length bytes)');
      }
      final ready=Completer<void>();
      _signal=ready;
      // Register signal only after testing current buffer to avoid races.
      if(_incoming.length>=length)break;
      await ready.future.timeout(deadline.difference(DateTime.now()));
    }
    _signal=null;
    final all=_incoming.takeBytes();
    final result=Uint8List.fromList(all.sublist(0,length));
    if(all.length>length)_incoming.add(all.sublist(length));
    return result;
  }

  /// Captured first Windows request after the 116-byte greeting.
  /// Wire size 1460; payload is all 0xFF after the 54-byte NU envelope.
  /// Sequence 0x15 was observed in a single trace: this MUST remain an
  /// explicit experimental one-shot; don't claim that it generalizes yet.
  static Uint8List capturedDeviceDescriptorRequest() {
    final packet=Uint8List(1460);
    packet.fillRange(0,packet.length,0xff);
    packet.setAll(0,NuHello.prefix);
    packet.setAll(16,const <int>[
      0x55,0x4e,0x54,0x24,0x00,0x08,0x02,0x00,
      0x15,0x00,0x80,0x00,0x33,0x00,0x00,0x00,
      0x01,0x00,0x01,0x00,0x08,0x00,0x12,0x00,
      0x80,0x06,0x00,0x00,0x00,0x10,0x02,0x08,
      0x80,0x06,0x00,0x01,0x00,0x00,0x12,0x00
    ]);
    return packet;
  }

  static bool verifiesCanon(Uint8List reply) {
    if(reply.length!=58)return false;
    // Captured 58-byte server completion: UNT$, cmd 02/01, seq 0x15.
    if(reply[0]!=0x55||reply[1]!=0x4e||
       reply[2]!=0x54||reply[3]!=0x24||
       reply[4]!=0||reply[5]!=0x1a||
       reply[6]!=2||reply[7]!=1||reply[8]!=0x15)return false;
    // Control setup echoed by hub; device descriptor at byte 40.
    if(reply[32]!=0x80||reply[33]!=0x06||
       reply[35]!=0x01||reply[40]!=18||reply[41]!=1)return false;
    return reply[48]==0xa9 && reply[49]==0x04 &&
           reply[50]==0x3a && reply[51]==0x18;
  }

  /// Connects a real TCP session and attempts one benign descriptor read.
  /// On success the socket remains open until [disconnect] is called.
  /// The hub might treat the open connection as ownership; avoid running
  /// Windows USB Server simultaneously.
  Future<String> connect(String host) async {
    if(isConnected)throw StateError('Already connected; disconnect first');
    if(!UsbPortDiagnostics.privateIpv4(host)){
      throw const FormatException('NU requires a private IPv4 hub address');
    }
    await disconnect();
    try {
      final peers=await NetworkInterface.list(
        type:InternetAddressType.IPv4,includeLoopback:false);
      final octets=host.split('.');
      final candidates=peers.expand((i)=>i.addresses)
        .map((a)=>a.address)
        .where(UsbPortDiagnostics.privateIpv4)
        .where((ip){
          final part=ip.split('.');
          return part[0]==octets[0]&&part[1]==octets[1]&&
            part[2]==octets[2];
        }).toList();
      if(candidates.isEmpty)throw StateError(
        'Phone has no private IPv4 address on the hub subnet');
      final socket=await Socket.connect(host,4660,
        timeout:const Duration(seconds:3));
      _socket=socket;
      socket.setOption(SocketOption.tcpNoDelay,true);
      _ended=false;
      _subscription=socket.listen(_receive,
        onError:(Object _){_ended=true;_signal?.complete();},
        onDone:(){_ended=true;_signal?.complete();});
      socket.add(NuHello.make(candidates.first));
      await socket.flush();
      final hello=await _readExact(100,const Duration(seconds:4));
      if(!NuHello.isGreetingReply(hello)){
        throw const FormatException('Hub did not accept NU greeting');
      }
      socket.add(capturedDeviceDescriptorRequest());
      await socket.flush();
      final reply=await _readExact(58,const Duration(seconds:5));
      if(!verifiesCanon(reply)){
        throw const FormatException(
          'Hub answered, but Canon 04A9:183A USB descriptor was not verified');
      }
      _connectedHost=host;
      return 'Canon 04A9:183A USB device descriptor verified over TCP 4660. '
        'NU socket is open. Exclusive claim and printing are NOT verified.';
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  /// Releases the local NU TCP session. A vendor-specific release opcode
  /// has not been proven; do not advertise this as exclusive claim release.
  Future<void> disconnect() async {
    _connectedHost=null;
    final subscription=_subscription;
    _subscription=null;
    await subscription?.cancel();
    final socket=_socket;
    _socket=null;
    socket?.destroy();
    _ended=true;
    if(_signal!=null&&!_signal!.isCompleted)_signal!.complete();
    _signal=null;
    _incoming.takeBytes();
  }
}
