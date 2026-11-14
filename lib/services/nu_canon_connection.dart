import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'nu_session.dart';
import 'nu_protocol.dart';
import 'nu_configuration.dart';
import 'usb_port_diagnostics.dart';

/// Experimental DA-70251 transport: captured NU greeting followed by a
/// *read-only* USB GET_DESCRIPTOR control request. Successful enumeration
/// demonstrates the vendor USB path, not exclusive ownership of the device.
/// Raw USB print bytes can be sent only through an explicit opt-in test.
class NuCanonConnection {
  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  final _incoming=BytesBuilder(copy:false);
  Completer<void>? _signal;
  bool _ended=false;
  String? _connectedHost;
  NuConfiguration? configuration;
  String? ieee1284DeviceId;
  bool _printing=false;
  bool get printing => _printing;
  NuInterface? get printerInterface => configuration?.printerInterface;

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
      final remaining=deadline.difference(DateTime.now());
      if(remaining<=Duration.zero){
        throw TimeoutException('NU response timed out');
      }
      await ready.future.timeout(remaining);
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

  /// Captured follow-up USB GET_DESCRIPTOR(CONFIGURATION) request. The
  /// Windows trace issues a nine-byte header read followed by the full
  /// 62-byte configuration read. The sequence bytes 0x16/0x17 are
  /// intentionally confined to this single captured startup sequence.
  static Uint8List capturedConfigurationRequest({
    required int sequence,required int length,
  }) {
    if(!((sequence==0x16 && length==9) ||
         (sequence==0x17 && length==62))){
      throw const FormatException('Unsupported captured config request');
    }
    final packet=capturedDeviceDescriptorRequest();
    packet[24]=sequence;
    packet[34]=2;
    packet[38]=length;
    packet[51]=2;
    packet[54]=length;
    return packet;
  }

  static Uint8List? configurationReplyPayload(Uint8List reply,{
    required int sequence,required int expectedLength,
  }) {
    if(reply.length!=40+expectedLength ||
       reply[0]!=0x55||reply[1]!=0x4e||reply[2]!=0x54||
       reply[3]!=0x24 || reply[6]!=2 || reply[7]!=1 ||
       reply[8]!=sequence ||
       reply[32]!=0x80||reply[33]!=6||
       reply[34]!=0||reply[35]!=2||
       reply[38]!=expectedLength||reply[39]!=0 ||
       reply[40]!=9||reply[41]!=2)return null;
    return Uint8List.fromList(reply.sublist(40));
  }

  /// USB printer-class GET_DEVICE_ID request observed in plm222.pcapng.
  /// Only the correlation identifier changes; no print bytes are transmitted.
  static Uint8List capturedPrinterIdRequest({int sequence=0x18}) {
    if(sequence<0||sequence>255) {
      throw const FormatException('NU request sequence must fit one byte');
    }
    final packet=Uint8List(1460);
    packet.fillRange(0,packet.length,0);
    packet.setAll(0,NuHello.prefix);
    packet.setAll(16,const <int>[
      0x55,0x4e,0x54,0x24,0x00,0x08,0x02,0x00,
      0x20,0x00,0x00,0x00,0x33,0x00,0x00,0x00,
      0x01,0x00,0x00,0x00,0x08,0x00,0xf1,0x03,
      0xa1,0x00,0x01,0x00,0x00,0x10,0x02,0x08,
      0xa1,0x00,0x00,0x00,0x00,0x01,0xf1,0x03
    ]);
    packet[24]=sequence;
    return packet;
  }

  /// Validate the echoed USB request and the IEEE 1284 big-endian length
  /// before interpreting any device identification text.
  static String parsePrinterIdReply(Uint8List reply,{int sequence=0x18}) {
    if(reply.length<44||reply.length>2048 ||
       reply[0]!=0x55||reply[1]!=0x4e||reply[2]!=0x54||
       reply[3]!=0x24||reply[6]!=2||reply[7]!=1||
       reply[8]!=sequence||reply[32]!=0xa1||reply[33]!=0||
       reply[37]!=1) {
      throw const FormatException('Unexpected NU printer ID reply');
    }
    final nuLength=(reply[4]<<8)|reply[5];
    if(nuLength+32!=reply.length ||
       ((reply[38]|(reply[39]<<8))!=1009)) {
      throw const FormatException('Invalid NU printer ID response length');
    }
    final usbLen=(reply[40]<<8)|reply[41];
    if(usbLen<4||usbLen>reply.length-40) {
      throw const FormatException('Invalid IEEE 1284 device ID length');
    }
    final text=String.fromCharCodes(reply.sublist(42,40+usbLen));
    if(!text.contains('MFG:Canon') || !text.contains('CMD:')) {
      throw const FormatException('Printer ID is not a Canon IEEE 1284 record');
    }
    return text;
  }

  /// Performs one read-only USB printer-class request over the existing
  /// verified NU connection. This does NOT claim an interface or print.
  Future<String> readPrinterId() async {
    final socket=_socket;
    if(!isConnected||socket==null||printerInterface==null) {
      throw StateError('Verify Canon USB configuration first');
    }
    try {
      socket.add(capturedPrinterIdRequest());
      await socket.flush();
      final header=await _readExact(40,const Duration(seconds:5));
      if(header[0]!=0x55||header[1]!=0x4e||
         header[2]!=0x54||header[3]!=0x24){
        throw const FormatException('No NU printer class response');
      }
      final length=((header[4]<<8)|header[5])+32;
      if(length<44 || length>2048){
        throw const FormatException('Printer ID response exceeds safe bounds');
      }
      final rest=await _readExact(length-40,const Duration(seconds:5));
      final combined=Uint8List.fromList([...header,...rest]);
      final result=parsePrinterIdReply(combined);
      ieee1284DeviceId=result;
      return result;
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  // Retained public test helpers; now using a single typed wire builder.
  static Uint8List capturedBulkOutFrame(Uint8List bytes,{
    required int sequence,
  }) => NuWire.bulkOut(bytes,sequence:sequence);

  static Uint8List capturedBulkPreparationRequest() =>
    NuWire.prepare(sequence:40);

  static bool isBulkPreparationResponse(Uint8List reply) {
    try {
      final r=NuReply.parse(reply);
      return r.command==9&&r.sequence==40&&r.bodyLength==32;
    }on FormatException{return false;}
  }

  static bool isBulkOutCompletion(Uint8List reply,{
    required int sequence,required int count,
  }) {
    try {
      final r=NuReply.parse(reply);
      return r.command==3&&r.sequence==sequence&&r.bodyLength==0&&
        r.reportedLength==count;
    }on FormatException{return false;}
  }

  /// NU replies have NO client preamble: 32-byte header plus declared body.
  /// TCP segmentation and coalescing are handled by the socket byte buffer.
  Future<Uint8List> _readNuResponse(Duration timeout) async {
    final header=await _readExact(32,timeout);
    if(header[0]!=85||header[1]!=78||header[2]!=84||header[3]!=36){
      throw const FormatException('NU reply magic mismatch');
    }
    final bodyLength=(header[4]<<8)|header[5];
    if(bodyLength>4096)throw const FormatException('NU body exceeds bound');
    if(bodyLength==0)return header;
    final body=await _readExact(bodyLength,timeout);
    return Uint8List.fromList(<int>[...header,...body]);
  }

  /// Each diagnostic line includes protocol direction, opcode, full 16-bit
  /// sequence, requested/returned length and the first 48 raw bytes.
  /// This may reveal up to 16 bytes of printer status in RX. Share carefully.
  final List<String> _printTrace=<String>[];
  String get printTrace => _printTrace.join('\n');
  void _logPrint(String s) {
    if(_printTrace.length<50000) {
      _printTrace.add(DateTime.now().toIso8601String()+' '+s);
    } else if(_printTrace.length==50000) {
      _printTrace.add('TRACE TRUNCATED after 50000 records');
    }
  }

  Future<void> _sendTracked(Uint8List frame,int command,int sequence,
      int count,NuPendingReplies pending) async {
    final socket=_socket;
    if(socket==null||_ended){
      throw const SocketException('NU session ended during print');
    }
    if(NuWire.txSequence(frame)!=sequence){
      throw StateError('NU TX sequence encoding mismatch');
    }
    pending.add(command,sequence,count,
      timeout:command==8?const Duration(seconds:30):
        const Duration(seconds:12));
    _logPrint('TX 02/'+command.toRadixString(16).padLeft(2,'0')+
      ' seq='+sequence.toString()+' count='+count.toString()+
      ' HEX48='+NuWire.hex(frame));
    socket.add(frame);
    await socket.flush();
  }

  /// Process an entire pending window. Independent correlation is essential:
  /// the 02/09 prep response can arrive after later 02/03/02/05 replies.
  Future<int> _drainTracked(NuPendingReplies pending,
      {bool requirePreparation=false,
      void Function(NuReply reply)? onReply}) async {
    var completedOut=0;
    // Do not block on 02/09 alone: Windows receives prep40 after
    // OUT and IN replies for sequences 41-50.
    while(requirePreparation?!pending.isEmpty:pending.hasDataPending) {
      final oldest=pending.oldest!;
      final remaining=oldest.deadline.difference(DateTime.now());
      if(remaining<=Duration.zero) {
        final msg='NU timed out awaiting 02/'+
          (oldest.command+1).toRadixString(16).padLeft(2,'0')+
          ' seq='+oldest.sequence.toString()+
          ', '+pending.length.toString()+' pending';
        _logPrint('TIMEOUT '+msg);
        throw TimeoutException(msg+'. Print delivery uncertain, no retry');
      }
      try {
        final bytes=await _readNuResponse(remaining);
        final reply=NuReply.parse(bytes);
        _logPrint('RX '+reply.summary+' HEX48='+NuWire.hex(bytes));
        final matched=pending.accept(reply);
        onReply?.call(reply);
        if(matched.command==2)completedOut+=matched.requested;
        if(matched.command==4) {
          _logPrint('READ seq='+reply.sequence.toString()+
            ' USB data bytes='+reply.bodyLength.toString()+
            ' (printer status is not decoded)');
        }
      }on TimeoutException{
        final msg='NU response timeout: oldest 02/'+
          (oldest.command+1).toRadixString(16).padLeft(2,'0')+
          ' seq='+oldest.sequence.toString()+
          '; '+pending.length.toString()+' still pending';
        _logPrint('TIMEOUT '+msg);
        throw TimeoutException(msg+'. Print delivery uncertain, no retry');
      }
    }
    return completedOut;
  }

  /// First-stage, explicitly approved NU handshake diagnostic.
  /// The real Windows 2026-11-14 capture uses seq40 prep, seq41
  /// 383-byte OUT on logical pipe 01 and seq42-44 1024-byte IN
  /// on logical pipe 81. It then has 16-byte and 4-byte exchanges
  /// whose payload semantics we have not decoded. Do NOT invent them
  /// or stream the remainder of a raster on the wrong endpoint.
  ///
  /// No complete print job is attempted. The first OUT is still an
  /// unverified experimental write, so never auto-retry uncertain data.
  Future<String> experimentalNuPrint(Uint8List raster) async {
    if(!isConnected||_socket==null||
        printerInterface?.bulkOut?.address!=1||
        ieee1284DeviceId==null||!ieee1284DeviceId!.contains('IVEC')){
      throw StateError('Connect, verify Canon USB and printer ID first');
    }
    if(_printing)throw StateError('NU diagnostic already in progress');
    if(raster.length<383||raster.length>20*1024*1024){
      throw const FormatException('Expected Canon IVEC bytes (383..20 MiB)');
    }
    _printing=true;
    _printTrace.clear();
    var acknowledged=0;
    _logPrint('START limited NU handshake diagnostic; rendered data='+
      raster.length.toString()+
      ' bytes, writing only first 383. Capture source: plm222.pcapng; '
      'logical IN pipe=0x81, no automatic retry. NOT FULL PRINT.');
    final pending=NuPendingReplies();
    final inLengths=<int,int>{};
    try {
      await _sendTracked(NuWire.prepare(sequence:40),
        8,40,64,pending);
      await _sendTracked(NuWire.bulkOut(
        Uint8List.sublistView(raster,0,383),sequence:41),
        2,41,383,pending);
      for(var seq=42;seq<=44;seq++) {
        await _sendTracked(NuWire.bulkIn(sequence:seq,
          endpoint:0x81,requestedLength:1024),
          4,seq,1024,pending);
      }
      acknowledged+=await _drainTracked(pending,onReply:(r){
        if(r.command==5)inLengths[r.sequence]=r.bodyLength;
      });
      // In the successful Windows capture seq42 and seq43 are empty,
      // but seq44 has 487 bytes. There is no proof this will always
      // hold on other printer states or firmware versions.
      _logPrint('PHASE1 seq42='+ (inLengths[42]??-1).toString()+
        ' seq43='+(inLengths[43]??-1).toString()+
        ' seq44='+(inLengths[44]??-1).toString()+
        ' (Windows reference 0/0/487).');
      if(!inLengths.values.any((length)=>length>0)){
        throw StateError('No printer data from seq42..44 on logical NU '
          'pipe 0x81. Aborting before seq45: inspect RX status in log. '
          'Print delivery uncertain, no retry.');
      }
      _logPrint('STOP after known seq40..44 handshake; Windows next '
        'writes 16 bytes at seq45 followed by 512-byte INs and '
        'multiple undecoded device-specific exchanges. Those cannot '
        'be constructed from the IVEC raster alone.');
      return 'NU handshake probe returned printer data; '
        'no complete print job was sent. Export the trace. '
        'The full Canon print protocol is not yet implemented.';
    }catch(e){
      _logPrint('FAILED after '+acknowledged.toString()+
        ' matching OUT bytes. '+e.toString()+'; NO RETRY');
      rethrow;
    }finally{
      await disconnect();
      _printing=false;
    }
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
        onError:(Object _){
          _ended=true;
          if(_signal!=null&&!_signal!.isCompleted)_signal!.complete();
        },
        onDone:(){
          _ended=true;
          if(_signal!=null&&!_signal!.isCompleted)_signal!.complete();
        });
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
      // Mirror Windows' read-only configuration enumeration. The descriptor
      // contains the class-07 printer interface and its bulk OUT endpoint.
      socket.add(capturedConfigurationRequest(sequence:0x16,length:9));
      await socket.flush();
      final shortReply=await _readExact(49,const Duration(seconds:5));
      final shortData=configurationReplyPayload(shortReply,
        sequence:0x16,expectedLength:9);
      if(shortData==null || shortData[2]!=62 || shortData[3]!=0){
        throw const FormatException(
          'Canon configuration header not validated (expected 62 bytes)');
      }
      socket.add(capturedConfigurationRequest(sequence:0x17,length:62));
      await socket.flush();
      final fullReply=await _readExact(102,const Duration(seconds:5));
      final descriptor=configurationReplyPayload(fullReply,
        sequence:0x17,expectedLength:62);
      if(descriptor==null){
        throw const FormatException(
          'Canon 62-byte configuration reply not validated');
      }
      final parsed=NuConfigurationDecoder.decode(descriptor);
      final printInterface=parsed.printerInterface;
      if(printInterface==null){
        throw const FormatException(
          'No printer-class USB interface with bulk OUT endpoint');
      }
      configuration=parsed;
      _connectedHost=host;
      return 'Canon 04A9:183A verified. USB configuration: '
        '${parsed.interfaces.length} interfaces; '
        'printer interface ${printInterface.number} '
        'bulk OUT ${printInterface.bulkOut!.hexAddress}. '
        'NU socket open. USB claim and bulk printing NOT verified.';
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  /// Releases the local NU TCP session. A vendor-specific release opcode
  /// has not been proven; do not advertise this as exclusive claim release.
  Future<void> disconnect() async {
    _connectedHost=null;
    configuration=null;
    ieee1284DeviceId=null;
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
