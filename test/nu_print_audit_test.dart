import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_print_audit.dart';
import 'package:digitus_print/services/nu_canon_connection.dart';

void main(){
  test('Identifies the IVEC XML stream, not the Windows USB setup',(){
    final xml=Uint8List.fromList('<?xml version="1.0" encoding="utf-8" ?>'
      .codeUnits);
    expect(NuPrintAudit.beginsWithIvecXml(xml),isTrue);
    final report=NuPrintAudit.diagnose(xml);
    expect(report,contains('TRANSMITTED_BYTES=0'));
    expect(report,contains('prefix8=3c 3f 78 6d 6c'));
    expect(report,contains('57 54 b9 ed 21 b2 10 0f'));
    expect(report,contains('not be substituted'));
    expect(report,contains('No physical printing attempted'));
  });
  test('Non-XML payload is unknown, not accepted as a print handshake',(){
    final arbitrary=Uint8List.fromList(
      <int>[0x57,0x54,0xb9,0xed,0x21,0xb2,0x10,0x0f]);
    final report=NuPrintAudit.diagnose(arbitrary);
    expect(NuPrintAudit.beginsWithIvecXml(arbitrary),isFalse);
    expect(report,contains('format unverified'));
    expect(report,contains('TRANSMITTED_BYTES=0'));
  });
  test('Audit never needs a live printer and writes no bytes',() async {
    final conn=NuCanonConnection();
    final data=Uint8List.fromList('<'.codeUnits);
    final response=await conn.analyzeNuPrintPlan(data);
    expect(response,contains('Zero USB bytes'));
    expect(conn.printTrace,contains('TRANSMITTED_BYTES=0'));
    expect(conn.printTrace,contains('No bytes sent to the hub'));
    expect(conn.isConnected,isFalse);
  });
  test('Reject empty job with no network activity',(){
    expect(()=>NuPrintAudit.diagnose(Uint8List(0)),throwsFormatException);
  });
}
