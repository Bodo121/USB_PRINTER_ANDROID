import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_frame_decoder.dart';
void main(){
 test('parses captured 116-byte client handshake without claiming semantics',(){
  final p=Uint8List(116);
  p.setAll(0,NuFrameDecoder.preamble);
  p.setAll(16,[0x55,0x4e,0x54,0x24,0x00,0x44,0x02,0x0a,0x14,0,0x80,0]);
  final frame=NuFrameDecoder.inspect(p)!;
  expect(frame.clientPreamble,isTrue);
  expect(frame.markerOffset,16);
  expect(frame.candidateOpcode,0x44);
 });
 test('parses captured server response',(){
  final p=Uint8List(100);
  p.setAll(0,[0x55,0x4e,0x54,0x24,0,0x44,0,0x0b,0x14,0,0x80,0]);
  final frame=NuFrameDecoder.inspect(p)!;
  expect(frame.clientPreamble,isFalse);
  expect(frame.markerOffset,0);
 });
 test('rejects arbitrary or truncated packets',(){
  expect(NuFrameDecoder.inspect(Uint8List(12)),isNull);
  expect(NuFrameDecoder.inspect(Uint8List(100)),isNull);
 });
}
