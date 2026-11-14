import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_protocol.dart';

/// Metadata extracted from the owner's original plm222.pcapng, Windows
/// client sequence 40..89. This is NOT raw USB payload. In particular
/// note that 02/02 also targets the *logical* 0x81 pipe; it cannot be
/// assumed to mean a physical printer bulk OUT endpoint.
const capture=<({int seq,int op,int count,int pipe})>[
  (seq:40,op:8,count:64,pipe:1),
  (seq:41,op:2,count:383,pipe:1),
  (seq:42,op:4,count:1024,pipe:129),
  (seq:43,op:4,count:1024,pipe:129),
  (seq:44,op:4,count:1024,pipe:129),
  (seq:45,op:2,count:16,pipe:1),
  (seq:46,op:4,count:512,pipe:129),
  (seq:47,op:4,count:512,pipe:129),
  (seq:48,op:2,count:4,pipe:129),
  (seq:49,op:2,count:4,pipe:129),
  (seq:50,op:2,count:4,pipe:129),
  (seq:51,op:0,count:8,pipe:1),
  (seq:52,op:2,count:4,pipe:129),
  (seq:53,op:4,count:8192,pipe:129),
  (seq:54,op:4,count:8192,pipe:129),
  (seq:55,op:2,count:661,pipe:129),
  (seq:56,op:2,count:149,pipe:129),
  (seq:57,op:4,count:8192,pipe:129),
  (seq:58,op:4,count:8192,pipe:129),
  (seq:59,op:2,count:321,pipe:129),
  (seq:60,op:4,count:8192,pipe:129),
  (seq:61,op:0,count:8,pipe:1),
  (seq:62,op:4,count:8192,pipe:129),
  (seq:63,op:0,count:8,pipe:1),
  (seq:64,op:2,count:391,pipe:129),
  (seq:65,op:4,count:8192,pipe:129),
  (seq:66,op:4,count:8192,pipe:129),
  (seq:67,op:2,count:191,pipe:129),
  (seq:68,op:2,count:2,pipe:129),
  (seq:69,op:2,count:5,pipe:129),
  (seq:70,op:2,count:780,pipe:129),
  (seq:71,op:2,count:268,pipe:129),
  (seq:72,op:2,count:1024,pipe:129),
  (seq:73,op:2,count:1024,pipe:129),
  (seq:74,op:2,count:1024,pipe:129),
  (seq:75,op:8,count:64,pipe:1),
  (seq:76,op:2,count:383,pipe:1),
  (seq:77,op:2,count:1024,pipe:129),
  (seq:78,op:4,count:1024,pipe:129),
  (seq:79,op:2,count:1024,pipe:129),
  (seq:80,op:4,count:1024,pipe:129),
  (seq:81,op:2,count:1024,pipe:129),
  (seq:82,op:4,count:1024,pipe:129),
  (seq:83,op:2,count:512,pipe:129),
  (seq:84,op:2,count:36,pipe:1),
  (seq:85,op:2,count:1024,pipe:129),
  (seq:86,op:4,count:512,pipe:129),
  (seq:87,op:2,count:1024,pipe:129),
  (seq:88,op:4,count:512,pipe:129),
  (seq:89,op:2,count:1024,pipe:129),
];

List<int> header(String hex){
  return hex.split(' ').map((e)=>int.parse(e,radix:16)).toList();
}

void main(){
  test('50 actual capture transaction metadata entries remain ordered',(){
    expect(capture.length,50);
    for(var i=0;i<capture.length;i++){
      expect(capture[i].seq,i+40);
      expect(<int>[0,2,4,8].contains(capture[i].op),isTrue);
    }
    // The previous implementation wrote a 1024-byte raster at seq45.
    // The real Windows client wrote only 16 bytes at that point.
    expect(capture[5],(seq:45,op:2,count:16,pipe:1));
    expect(capture[6],(seq:46,op:4,count:512,pipe:129));
    expect(capture[7],(seq:47,op:4,count:512,pipe:129));
    expect(capture[8],(seq:48,op:2,count:4,pipe:129));
    expect(capture[13].count,8192); // NOT supported by our live sender.
  });
  test('capture-exact initial 02/08 preparation header',(){
    final frame=NuWire.prepare(sequence:40);
    expect(frame.sublist(0,48),header(
      '10 0f 0e 0d 0c 0b 0a 09 08 07 06 05 04 03 02 01 '
      '55 4e 54 24 00 40 02 08 28 00 00 00 00 00 01 00 '
      '01 00 0b 00 40 00 00 00 04 f8 80 28 40 10 92 34'));
  });
  test('capture-exact initial 383-byte OUT header',(){
    final frame=NuWire.bulkOut(Uint8List(383),sequence:41);
    expect(frame.sublist(0,48),header(
      '10 0f 0e 0d 0c 0b 0a 09 08 07 06 05 04 03 02 01 '
      '55 4e 54 24 01 7f 02 02 29 00 00 00 00 00 01 00 '
      '01 00 30 f0 7f 01 00 00 00 00 80 29 00 12 72 20'));
  });
  test('capture-exact IN header on logical NU pipe 81, seq42..44',(){
    for(final seq in <int>[42,43,44]){
      final frame=NuWire.bulkIn(sequence:seq,endpoint:0x81,
        requestedLength:1024);
      final sample=header(
        '10 0f 0e 0d 0c 0b 0a 09 08 07 06 05 04 03 02 01 '
        '55 4e 54 24 04 00 02 04 2a 00 00 00 00 00 01 00 '
        '81 00 30 f0 00 04 00 00 00 00 80 2a 00 12 82 24');
      sample[24]=seq;
      sample[43]=seq;
      expect(frame.sublist(0,48),sample);
      expect(frame.length,1460);
    }
  });
  test('window after initial read is different from a 1024-byte OUT',(){
    final frame=NuWire.bulkOut(Uint8List(16),sequence:45);
    expect(frame[23],2);
    expect(frame[20],0);
    expect(frame[21],16);
    final read=NuWire.bulkIn(sequence:46,endpoint:0x81,
      requestedLength:512);
    expect(read.sublist(20,24),[2,0,2,4]);
    expect(read.sublist(44,48),[0,0x12,0x82,0x24]);
  });
}
