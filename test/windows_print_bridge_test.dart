import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/windows_print_bridge.dart';

void main(){
  test('Only trusted private-LAN addresses are accepted',(){
    for(final ip in <String>[
      '192.168.0.117','10.0.0.2','172.16.0.4','172.31.255.254',
      '127.0.0.1',
    ]){
      expect(()=>WindowsPrintBridge(host:ip,
        token:'abcdefghijabcdefghijabcdefghijabcd'),returnsNormally);
    }
    for(final ip in <String>[
      '192.0.2.5','8.8.8.8','172.32.0.1','256.5.7.2','localhost',
      '0.0.0.0',
    ]){
      expect(()=>WindowsPrintBridge(host:ip,
        token:'abcdefghijabcdefghijabcdefghijabcd'),throwsFormatException);
    }
  });

  test('An empty/short pairing token cannot print',(){
    expect(()=>WindowsPrintBridge(host:'192.168.0.117',token:'abc'),
      throwsFormatException);
    expect(()=>WindowsPrintBridge(host:'192.168.0.117',
      token:'abcdefghijabcdefghijabcdefghijabcd',port:0),
      throwsFormatException);
  });

  test('Each job has unpredictable, distinct idempotency key',(){
    final a=WindowsPrintBridge.newJobId(),b=WindowsPrintBridge.newJobId();
    expect(a.length,40);
    expect(RegExp(r'^[0-9a-f]{40}$').hasMatch(a),isTrue);
    expect(a,isNot(b));
  });

  test('Windows spooler acknowledgement is not physical output',(){
    final p=WindowsBridgeJob.fromJson({
      'id':'random0123456789','state':'submitted',
      'message':'submitted to Windows spooler; paper output not verified'});
    expect(p.finished,isTrue);
    expect(p.message,contains('paper output not verified'));
    final q=WindowsBridgeJob.fromJson({
      'id':'random0123456789','state':'queued','message':'Pending'});
    expect(q.finished,isFalse);
  });
}
