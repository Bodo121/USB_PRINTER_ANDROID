import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// LPD does not define a "list queues" command. These are safe read-only
/// candidates; a TCP connection or a non-error status is not proof of
/// a physical printer, or proof of a particular Canon model.
class LprCandidate {
  const LprCandidate(this.host, this.queue, this.evidence);
  final String host;
  final String queue;
  final String evidence;
}

class HubDiscovery {
  static const candidateQueues = <String>[
    'lp', 'lpt1', 'LPT1', 'USB1', 'usb1', 'printer', 'print', 'P1',
    'lp1', 'LPR', 'queue1', 'USB', 'pr1',
  ];

  static bool privateAddress(String address) {
    final s=address.split('.');
    if(s.length!=4)return false;
    final a=int.tryParse(s[0]), b=int.tryParse(s[1]);
    return a==10 || a==192&&b==168 || a==172&&b!=null&&b>=16&&b<=31;
  }

  static Future<List<String>> localPrefixes() async {
    final interfaces=await NetworkInterface.list(
      type: InternetAddressType.IPv4, includeLoopback:false);
    final prefixes=<String>{};
    for(final nic in interfaces) {
      for(final address in nic.addresses) {
        if(!privateAddress(address.address))continue;
        prefixes.add(address.address.split('.').take(3).join('.'));
      }
    }
    return prefixes.take(2).toList();
  }

  static Future<bool> hasLpr(String host) async {
    Socket? socket;
    try {
      socket=await Socket.connect(host,515,
        timeout:const Duration(milliseconds:380));
      return true;
    } catch (_) {return false;}
    finally {socket?.destroy();}
  }

  /// Reads only queue status via RFC1179 0x03. Limit output and duration.
  static Future<String?> query(String host,String queue) async {
    Socket? socket;
    StreamSubscription<List<int>>? subscription;
    try {
      socket=await Socket.connect(host,515,
        timeout:const Duration(milliseconds:550));
      final output=<int>[];
      final completer=Completer<void>();
      subscription=socket.listen((chunk) {
        if(output.length<2048) {
          output.addAll(chunk.take(2048-output.length));
        }
        if(output.length>=2048&&!completer.isCompleted)completer.complete();
      },onError:(Object error){
        if(!completer.isCompleted)completer.complete();
      },onDone:(){
        if(!completer.isCompleted)completer.complete();
      });
      socket.add([3,...ascii.encode('$queue\n')]);
      await socket.flush();
      await completer.future.timeout(const Duration(milliseconds:850),
        onTimeout:(){});
      return utf8.decode(output,allowMalformed:true).trim();
    } catch (_) {return null;}
    finally {
      await subscription?.cancel();
      socket?.destroy();
    }
  }

  /// A recognized response might indicate a queue exists, but is not a
  /// validation of the printer model or a guarantee the queue is writable.
  static String? positiveEvidence(String? response) {
    if(response==null||response.isEmpty)return null;
    final r=response.toLowerCase();
    if(RegExp(r'(unknown queue|no such queue|invalid queue|queue not found|does not exist|not found|not available|error|rejected|unsupported)').hasMatch(r)){
      return null;
    }
    if(RegExp(r'(no entries|is ready|is printing|queue is|active|spooling|printer ready|job [0-9])').hasMatch(r)){
      return response.substring(0,response.length>120?120:response.length);
    }
    return null;
  }

  static Future<List<LprCandidate>> probeQueues(String host) async {
    final results=<LprCandidate>[];
    // Limit concurrent LPR probes to avoid overwhelming an older USB hub.
    for(var i=0;i<candidateQueues.length;i+=3){
      final batch=candidateQueues.skip(i).take(3);
      final found=await Future.wait(batch.map((q)async{
        final evidence=positiveEvidence(await query(host,q));
        return evidence==null?null:LprCandidate(host,q,evidence);
      }));
      results.addAll(found.whereType<LprCandidate>());
    }
    return results;
  }
}
