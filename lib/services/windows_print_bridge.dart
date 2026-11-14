import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Trusted-LAN client for the user's Windows Canon print queue.
/// Never sends proprietary NU USB commands to the DIGITUS hub.
class WindowsPrintBridge {
  WindowsPrintBridge({required this.host, required this.token, this.port=8765}) {
    final ip=InternetAddress.tryParse(host.trim());
    if(ip==null || ip.type!=InternetAddressType.IPv4 ||
       !_privateIPv4(ip.rawAddress) || port<1 || port>65535) {
      throw const FormatException('Enter the Windows PC private IPv4 address, '
          'not the DIGITUS hub IP (10.x, 172.16-31.x, 192.168.x).');
    }
    if(token.trim().length<32 ||
       !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(token.trim())) {
      throw const FormatException('Enter the full Windows bridge pairing token.');
    }
  }

  final String host, token;
  final int port;
  static bool _privateIPv4(List<int> b)=>b.length==4&&
      (b[0]==10 || (b[0]==172&&b[1]>=16&&b[1]<=31) ||
       (b[0]==192&&b[1]==168) || b[0]==127);
  Uri _uri(String path)=>Uri(scheme:'http',host:host.trim(),port:port,path:path);

  static String newJobId() => List<int>.generate(20,(_)=>Random.secure().nextInt(256))
      .map((b)=>b.toRadixString(16).padLeft(2,'0')).join();

  Future<Map<String,dynamic>> _request(String method,String path,
      {Uint8List? pdf,String? jobId}) async {
    final client=HttpClient()..connectionTimeout=const Duration(seconds:5)
       ..idleTimeout=const Duration(seconds:1);
    try{
      final req=await client.openUrl(method,_uri(path))
          .timeout(const Duration(seconds:8));
      req.headers.set('X-Digitus-Key',token.trim());
      req.headers.set('Accept','application/json');
      req.headers.set('Connection','close');
      if(jobId!=null)req.headers.set('X-Digitus-Job',jobId);
      if(pdf!=null){
        req.headers.contentType=ContentType('application','pdf');
        req.contentLength=pdf.length;
        req.add(pdf);
      }
      final resp=await req.close().timeout(const Duration(seconds:35));
      final body=await resp.transform(utf8.decoder).join()
          .timeout(const Duration(seconds:10));
      dynamic obj;
      try{ obj=jsonDecode(body); }
      on FormatException {
        throw const FormatException('The Windows PC returned invalid data. '
            'Check the IP, port and firewall.');
      }
      if(obj is! Map<String,dynamic>) {
        throw const FormatException('Invalid print bridge response');
      }
      if(resp.statusCode>=400){
        throw HttpException('Bridge HTTP '+resp.statusCode.toString()+
          ': '+(obj['error']?.toString()??'Request rejected'));
      }
      return obj;
    }on SocketException catch(e){
      throw SocketException('Cannot reach Windows PC '+host+':'+port.toString()+
          '. Check bridge and Private network firewall. '+e.message);
    }finally{client.close(force:true);}
  }

  Future<WindowsBridgeHealth> check() async{
    final d=await _request('GET','/v1/health');
    return WindowsBridgeHealth(
      ready:d['ready']==true&&d['ok']==true,
      printer:d['printer']?.toString()??'(unknown)',
      note:d['note']?.toString()??'');
  }

  /// The same jobId MUST be persisted by the UI before posting.
  /// If delivery times out, query status rather than automatically retry.
  Future<WindowsBridgeJob> submit(Uint8List pdf,String jobId) async{
    if(pdf.length<32||pdf.length>25*1024*1024 ||
       String.fromCharCodes(pdf.take(5))!='%PDF-'){
      throw const FormatException('Choose a valid PDF under 25 MiB.');
    }
    _validateJobId(jobId);
    return WindowsBridgeJob.fromJson(await _request(
       'POST','/v1/jobs',pdf:pdf,jobId:jobId));
  }

  Future<WindowsBridgeJob> status(String jobId) async{
    _validateJobId(jobId);
    return WindowsBridgeJob.fromJson(
      await _request('GET','/v1/jobs/'+jobId));
  }
  static void _validateJobId(String id){
    if(!RegExp(r'^[a-zA-Z0-9_-]{12,64}$').hasMatch(id)){
      throw const FormatException('Invalid Windows print job ID');
    }
  }
}

class WindowsBridgeHealth {
  const WindowsBridgeHealth({required this.ready,required this.printer,required this.note});
  final bool ready;
  final String printer,note;
}

class WindowsBridgeJob {
  const WindowsBridgeJob({required this.id,required this.state,required this.message});
  final String id,state,message;
  bool get finished=>state=='submitted'||state=='failed'||state=='uncertain';
  factory WindowsBridgeJob.fromJson(Map<String,dynamic> d)=>WindowsBridgeJob(
    id:d['id']?.toString()??'',
    state:d['state']?.toString()??'uncertain',
    message:d['message']?.toString()??'No status returned');
}
