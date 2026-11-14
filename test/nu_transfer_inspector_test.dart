import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_transfer_inspector.dart';

void main(){
 test('decodes captured Windows USB descriptor request metadata',(){
  final data=Uint8List(1460);
  data.setAll(0,List<int>.generate(16,(i)=>16-i));
  data.setAll(16,[0x55,0x4e,0x54,0x24,0x00,0x08,0x02,0x00,0x15]);
  data.setAll(32,[1,0,1,0,8,0,18,0,0x80,0x06,0,1,0,0,18,0]);
  final result=NuTransferInspector.inspect(data,fromHub:false)!;
  expect(result.sequence,0x15);
  expect(result.declaredBodyLength,8);
  expect(result.usbSetup?.isGetDescriptor,isTrue);
  expect(result.usbSetup?.descriptorType,1);
 });
 test('recognizes hub transfer reply header without pretending it is a claim',(){
  final data=Uint8List(58);
  data.setAll(0,[0x55,0x4e,0x54,0x24,0,0x1a,2,1,0x15]);
  final result=NuTransferInspector.inspect(data,fromHub:true)!;
  expect(result.directionFromHub,isTrue);
  expect(result.type,1);
  expect(result.usbSetup,isNull);
 });
 test('rejects missing preamble and marker',(){
  expect(NuTransferInspector.inspect(Uint8List(64),fromHub:false),isNull);
 });
}
