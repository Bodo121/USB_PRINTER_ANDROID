import 'dart:typed_data';
import 'services/hub_discovery.dart';
import 'services/hub_web_probe.dart';
import 'services/usbip_discovery.dart';
import 'services/vendor_usb_discovery.dart';
import 'services/dcp_discovery.dart';
import 'services/dcp_discovery.dart';
import 'services/usb_port_diagnostics.dart';
import 'package:flutter/services.dart';
import 'services/lpr_transport.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const PrintApp());
class PrintApp extends StatefulWidget {
  const PrintApp({super.key});
  @override State<PrintApp> createState()=>_PrintAppState();
}
class _PrintAppState extends State<PrintApp> {
  bool dark=false;
  @override Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,title:'Digitus Print',
    theme:ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xff6750a4)),
    darkTheme:ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xffb9a5f5),brightness:Brightness.dark),
    themeMode:dark?ThemeMode.dark:ThemeMode.light,
    home:Home(onTheme:()=>setState(()=>dark=!dark)));
}
class Home extends StatefulWidget {
 const Home({required this.onTheme,super.key});
 final VoidCallback onTheme;
 @override State<Home> createState()=>_HomeState();
}
class _HomeState extends State<Home> {
 final ip=TextEditingController(),queue=TextEditingController(),
   servicePorts=TextEditingController(text:'4660,3240,515,9100');
 int selectedUsbSocket=1;
 bool probingServices=false;
 bool checkingUpdate=false,downloadingUpdate=false,updateDownloaded=false;
 String updateMessage='';
 Map<String,dynamic>? availableUpdate;
 List<NetworkServicePort> networkServices=[];
 int tab=0; bool busy=false,landscape=false,canonConsent=false,canonBusy=false,canonGrayscale=false,canonDataFirst=false,canonReservedPort=false,showAdvanced=false,showPreview=false;
 double progress=0;
 String message='Ready to scan',paper='A4';
 HubSnapshot? hubInfo;
 UsbIpResult? usbIpDiagnostic;
 NuVendorObservation? vendorUsbDiagnostic;
 DcpListenResult? dcpDiagnostic;
 bool dcpListening=false;
 DcpListenResult? dcpResult;
 bool listeningDcp=false;
 bool vendorProbeRunning=false;
 int scanGeneration=0;
 Uint8List? pdfBytes; String filename='';
 List<String> hosts=[],history=[];
 final Map<String,List<LprCandidate>> queueMatches={};
 @override void initState(){super.initState();load();}
 Future<void> load() async {
   final prefs=await SharedPreferences.getInstance();
   if(!mounted)return;
   setState((){
     ip.text=prefs.getString('ip')??'192.168.0.74';
     queue.text=prefs.getString('queue')??'a9043a1802';
     servicePorts.text=prefs.getString('usbIpTcpPorts')??'4660,3240,515';
     selectedUsbSocket=(prefs.getInt('usbSocket')??1).clamp(1,4);
     history=prefs.getStringList('history')??[];
     canonDataFirst=prefs.getBool('canonDataFirst')??false;
     canonReservedPort=prefs.getBool('canonReservedPort')??false;
   });
   if(ip.text.trim().isNotEmpty) { await checkSavedHub(); }
   checkForUpdates(silent:true);
 }
 static bool newerVersion(String remote, String current) {
   List<int> parse(String value) => value.split('+').first.split('-').first
     .split('.').map((v)=>int.tryParse(v)??0).toList();
   final a=parse(remote), b=parse(current);
   for(var i=0;i<3;i++){
     final av=i<a.length?a[i]:0, bv=i<b.length?b[i]:0;
     if(av!=bv)return av>bv;
   }
   return false;
 }
 Future<void> checkForUpdates({bool silent=false}) async {
   if(checkingUpdate)return;
   setState(()=>checkingUpdate=true);
   try{
     final result=await const MethodChannel('digitus_print/updates')
       .invokeMapMethod<String,dynamic>('check');
     if(!mounted || result==null)return;
     final info=Map<String,dynamic>.from(result);
     setState((){
       availableUpdate=info;
       updateDownloaded=false;
       final latest=info['version']?.toString()??'0.0.0';
       final installed=info['current']?.toString()??'0.0.0';
       updateMessage=newerVersion(latest,installed)
         ? 'Version $latest is available (installed: $installed).'
         : 'You are on the latest published version ($installed).';
     });
   }catch(e){
     if(mounted && !silent)setState(()=>updateMessage='Could not check GitHub Releases: $e');
   }finally{if(mounted)setState(()=>checkingUpdate=false);}
 }
 Future<void> downloadUpdate() async {
   final item=availableUpdate;
   if(item==null||downloadingUpdate)return;
   setState((){
     downloadingUpdate=true;
     updateDownloaded=false;
     updateMessage='Downloading and verifying the release APK...';
   });
   try{
     final bytes=await const MethodChannel('digitus_print/updates')
        .invokeMethod<int>('download',{
          'url':item['url'],'digest':item['digest'],
          'version':item['version']});
     if(mounted)setState((){
       updateDownloaded=true;
       updateMessage='Downloaded and verified ${bytes??0} bytes. Tap Install to open Android installer.';
     });
   }catch(e){if(mounted)setState(()=>updateMessage='Update download failed: $e');}
   finally{if(mounted)setState(()=>downloadingUpdate=false);}
 }
 Future<void> installUpdate() async {
   try{
     final result=await const MethodChannel('digitus_print/updates')
       .invokeMethod<String>('install');
     if(mounted)setState(()=>updateMessage=result=='permission_required'
       ? 'Allow updates from DigitusPrint in Android settings, then return and tap Install.'
       : 'Android installer opened. Confirm the update there.');
   }catch(e){if(mounted)setState(()=>updateMessage='Unable to open installer: $e');}
 }
 Future<void> save() async {
   final prefs=await SharedPreferences.getInstance();
   await prefs.setString('ip',ip.text.trim());
   await prefs.setString('queue',queue.text.trim());
   await prefs.setString('usbIpTcpPorts',servicePorts.text.trim());
   await prefs.setInt('usbSocket',selectedUsbSocket);
   if(mounted)setState(()=>message='Connection saved');
 }
 Future<void> checkSavedHub() async {
   final host=ip.text.trim();
   if(host.isEmpty)return;
   final details=await const HubWebProbe().inspect(host);
   if(!mounted || ip.text.trim()!=host)return;
   setState((){
     hubInfo=details;
     if(details!=null)message='USB sharing hub found at $host. LPR queue and printed output are not yet verified.';
   });
 }
 void cancelDiscovery() {
   scanGeneration++;
   setState((){busy=false;message='Discovery cancelled';});
 }
 Future<void> discover() async {
   if(busy)return;
   final generation=++scanGeneration;
   setState((){
     busy=true;hosts=[];queueMatches.clear();progress=0;
     message='Checking your USB hub...';
   });
   bool active()=>mounted && scanGeneration==generation;
   try {
     // Fast path: recognize the user's known hub before scanning /24 ranges.
     final previous=ip.text.trim();
     final saved=await const HubWebProbe().inspect(previous);
     if(!active())return;
     if(saved!=null){
       setState((){
         hubInfo=saved;hosts=[previous];progress=0.6;
         message='USB hub found. Checking read-only LPR queue status...';
       });
       if(await HubDiscovery.hasLpr(previous)) {
         final matches=await HubDiscovery.probeQueues(previous);
         if(!active())return;
         setState(()=>queueMatches[previous]=matches);
         await autoSelectSingle(previous,matches);
         if(!active())return;
         setState((){
           progress=1;
           message=matches.length==1
             ? 'Hub recognized; one candidate queue saved. Printing remains unverified.'
             : matches.isEmpty
               ? 'Hub identified, but the firmware did not reveal a queue. Use Advanced Settings if needed.'
               : 'Hub recognized; choose one of the candidate queues shown below.';
         });
       } else {
         if(!active())return;
         setState(()=>message='Hub web interface works, but LPR port 515 is unavailable.');
       }
       return;
     }

     final prefixes=await HubDiscovery.localPrefixes();
     if(!active())return;
     if(prefixes.isEmpty){
       setState(()=>message='No private Wi-Fi network found.');
       return;
     }
     setState(()=>message='Searching local network for USB sharing hubs...');
     final targets=<String>[];
     for(final prefix in prefixes) {
       for(int x=1;x<=254;x++){targets.add('$prefix.$x');}
     }
     final discovered=<String>[];
     for(var i=0;i<targets.length;i+=64){
       final batch=targets.skip(i).take(64);
       final candidates=await Future.wait(batch.map((host)async{
         final lpr=await HubDiscovery.hasLpr(host);
         if(!lpr)return null;
         return host;
       }));
       if(!active())return;
       discovered.addAll(candidates.whereType<String>());
       setState((){
         hosts=List.of(discovered);
         progress=0.7*((i+64).clamp(0,targets.length))/targets.length;
       });
     }
     for(var i=0;i<discovered.length&&i<6;i++){
       final host=discovered[i];
       final details=await const HubWebProbe().inspect(host);
       if(!active())return;
       if(details!=null){
         setState(()=>hubInfo=details);
         // Prefer the identified hub; never identify a printer by its
         // self-reported USB name as the G2420 profile remains user selected.
         ip.text=host;
       }
       final matches=await HubDiscovery.probeQueues(host);
       if(!active())return;
       setState(()=>queueMatches[host]=matches);
       await autoSelectSingle(host,matches);
       if(!active())return;
       setState(()=>progress=0.7+0.3*(i+1)/discovered.take(6).length);
     }
     if(!active())return;
     setState((){
       message=discovered.isEmpty
         ? 'No LPR servers found. Check hub power and Wi-Fi.'
         : hubInfo!=null
           ? 'USB hub identified. Select a verified candidate queue if available.'
           : 'Found LPR endpoints, but none verified as the DIGITUS hub.';
       progress=1;
     });
   }catch(e){
     if(active())setState(()=>message='Discovery error: $e');
   }finally {
     if(active())setState(()=>busy=false);
   }
 }
 Future<void> autoSelectSingle(String host,List<LprCandidate> matches) async {
   // A queue-status reply may be identical for ANY queue on old firmware.
   // Auto-select only when exactly one candidate has convincing evidence.
   if(matches.length!=1)return;
   ip.text=host;queue.text=matches.single.queue;
   final prefs=await SharedPreferences.getInstance();
   await prefs.setString('ip',host);
   await prefs.setString('queue',queue.text);
 }
 Future<void> checkUsbNetworkPorts() async {
   if(probingServices)return;
   List<int> ports;
   try {ports=UsbPortDiagnostics.parsePorts(servicePorts.text);}
   catch(e){if(mounted)setState(()=>message='Invalid TCP ports: $e');return;}
   final host=ip.text.trim();
   setState((){
     probingServices=true;
     networkServices=[];
     message='Checking TCP services on your USB hub (connection-only)...';
   });
   try {
     final results=await const UsbPortDiagnostics().check(
       host:host,ports:ports);
     if(!mounted || host!=ip.text.trim())return;
     setState((){
       networkServices=results;
       message='${results.where((e)=>e.open).length} of ${results.length} TCP ports accepted connections. Open ports do not prove USB-over-IP protocol compatibility.';
     });
     final prefs=await SharedPreferences.getInstance();
     await prefs.setString('usbIpTcpPorts',servicePorts.text.trim());
   }catch(e){if(mounted)setState(()=>message='TCP port check failed: $e');}
   finally {if(mounted)setState(()=>probingServices=false);}
 }
 Future<void> listenForDcp() async {
   if(listeningDcp)return;
   final host=ip.text.trim();
   setState((){
     listeningDcp=true;
     dcpResult=null;
     message='Listening for DA-70251 discovery on UDP 52340...';
   });
   try {
     final result=await const DcpDiscovery().listen(expectedHub:host);
     if(!mounted||host!=ip.text.trim())return;
     setState((){
       dcpResult=result;
       message=result.detail;
     });
   }catch(e){if(mounted)setState(()=>message='DCP listener error: $e');}
   finally{if(mounted)setState(()=>listeningDcp=false);}
 }
 Future<void> listenDcp() async {
   if(dcpListening)return;
   final host=ip.text.trim();
   setState((){
     dcpListening=true;
     dcpDiagnostic=null;
     message='Listening for DA-70251 DCP$ announcements on UDP 52340...';
   });
   try{
     final result=await const DcpDiscovery().listen(expectedHub:host);
     if(!mounted||host!=ip.text.trim())return;
     setState((){
       dcpDiagnostic=result;
       message=result.detail;
     });
   }catch(e){if(mounted)setState(()=>message='DCP listening failed: $e');}
   finally{if(mounted)setState(()=>dcpListening=false);}
 }
 Future<void> inspectNuVendor() async {
   if(vendorProbeRunning)return;
   final host=ip.text.trim();
   setState((){
     vendorProbeRunning=true;
     vendorUsbDiagnostic=null;
     message='Observing NU V1.25 TCP port 4660 (no USB commands sent)...';
   });
   try{
     final result=await const NuVendorProbe().observe(host);
     if(!mounted||host!=ip.text.trim())return;
     setState((){
       vendorUsbDiagnostic=result;
       message=result.detail;
     });
   }catch(e){if(mounted)setState(()=>message='NU protocol observation failed: $e');}
   finally{if(mounted)setState(()=>vendorProbeRunning=false);}
 }
 Future<void> inspectNativeUsbIp() async {
   final host=ip.text.trim();
   if(host.isEmpty){setState(()=>message='Find the USB hub first');return;}
   setState(()=>message='Querying standard USB/IP device list (read-only)...');
   final result=await const UsbIpDiscovery().probe(host);
   if(!mounted || ip.text.trim()!=host)return;
   setState((){
     usbIpDiagnostic=result;
     message=result.supported
       ? 'Standard USB/IP responded: ${result.devices.length} exported device(s)'
       : result.detail;
   });
 }
 Future<void> inspectQueue() async {
   final host = ip.text.trim(), q = queue.text.trim();
   if(host.isEmpty || q.isEmpty) {setState(()=>message='Enter or discover a hub and provide its LPR queue name');return;}
   setState(()=>message='Inspecting LPR queue...');
   try {
     final response = await const LprTransport().queryQueue(host:host,queue:q);
     if(mounted)setState(()=>message=response.trim().isEmpty
       ? 'Empty LPR status response: this is NOT a print-job ACK. Queue may still be valid; use the explicit one-page test to check the LPR transfer.'
       : 'LPD queue response: ${response.trim().length>400?response.trim().substring(0,400):response.trim()}');
   } catch(e) { if(mounted)setState(()=>message='Queue check failed: $e'); }
 }
 Future<void> pick() async {
   try{
     final f=await FilePicker.pickFile(type:FileType.custom,
       allowedExtensions:['pdf','jpg','jpeg','png','txt']);
     if(f==null)return;
     final bytes=await f.readAsBytes();
     final ext=f.extension?.toLowerCase();
     if(ext=='pdf'){pdfBytes=bytes;}else{
       final doc=pw.Document();
       final fmt=paper=='Letter'?PdfPageFormat.letter:PdfPageFormat.a4;
       final size=landscape?fmt.landscape:fmt;
       if(ext=='txt'){
         doc.addPage(pw.MultiPage(pageFormat:size,build:(_)=>[
           pw.Text(String.fromCharCodes(bytes),style:const pw.TextStyle(fontSize:11))
         ]));
       }else{
         doc.addPage(pw.Page(pageFormat:size,build:(_)=>pw.Center(
           child:pw.Image(pw.MemoryImage(bytes),fit:pw.BoxFit.contain))));
       }
       pdfBytes=await doc.save();
     }
     if(mounted)setState((){filename=f.name;tab=1;showPreview=false;message='Prepared: $filename';});
   }catch(e){if(mounted)setState(()=>message='File error: $e');}
 }
 Future<void> createCanonTestPage() async {
   try {
     final doc=pw.Document();
     doc.addPage(pw.Page(pageFormat:PdfPageFormat.a4,build:(context)=>pw.Column(
       crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
         pw.Text('DigitusPrint - Canon PIXMA G2420',
           style:pw.TextStyle(fontSize:20,fontWeight:pw.FontWeight.bold)),
         pw.SizedBox(height:12),
         pw.Text('One-page experimental driver test - A4, normal quality'),
         pw.SizedBox(height:20),
         pw.Text('Black text / lines / color patches'),
         pw.Divider(thickness:2),
         pw.SizedBox(height:20),
         pw.Row(children:[
           pw.Container(width:72,height:32,color:PdfColors.black),
           pw.Container(width:72,height:32,color:PdfColors.cyan),
           pw.Container(width:72,height:32,color:PdfColor(1, 0, 1)),
           pw.Container(width:72,height:32,color:PdfColors.yellow),
         ]),
         pw.SizedBox(height:20),
         pw.Text('0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
         pw.Text('abcdefghijklmnopqrstuvwxyz'),
         pw.SizedBox(height:24),
         pw.Text('If this page prints successfully, confirm the result in the app.'),
         pw.Text('A server LPR acknowledgement alone does not prove printing.'),
       ],
     )));
     final bytes=await doc.save();
     if(mounted)setState((){
       pdfBytes=bytes;filename='DigitusPrint-G2420-test.pdf';
       showPreview=false;tab=1;message='Test page prepared. Confirm experimental printing before sending.';
     });
   } catch(e) {
     if(mounted)setState(()=>message='Unable to prepare test page: $e');
   }
 }
 Future<void> testCanonNative() async {
   if (pdfBytes==null || !canonConsent || canonBusy) return;
   if (ip.text.trim().isEmpty || queue.text.trim().isEmpty) {
     setState(()=>message='No confirmed LPR queue. Discover the hub or use Advanced Settings.');return;
   }
   setState((){canonBusy=true;message='Converting first PDF page to Canon G2020-series IVEC raster on Android...';});
   try {
     final result=await const MethodChannel('digitus_print/canon').invokeMethod<String>(
       'experimentalPrint',<String,dynamic>{
         'pdf':pdfBytes,'host':ip.text.trim(),'queue':queue.text.trim(),
         'gray':canonGrayscale,'approved':canonConsent,
         'dataFirst':canonDataFirst,
         'reservedSourcePort':canonReservedPort,
       });
     history.insert(0,'${DateTime.now().toLocal().toString().substring(0,16)} · LPR transaction ACK, physical output unknown: $filename');
     final prefs=await SharedPreferences.getInstance();
     history=history.take(20).toList();
     await prefs.setStringList('history',history);
     if(mounted)setState(()=>message=result??'LPR returned without a result');
   } catch(e) { if(mounted)setState(()=>message='Canon test failed: $e'); }
   finally { if(mounted)setState(()=>canonBusy=false); }
 }
 Future<void> printFile() async {
   if(pdfBytes==null)return;
   try{
     // Android PrintManager needs a compatible printer service or external driver.
     await Printing.layoutPdf(onLayout:(_)=>pdfBytes!,name:filename);
     final prefs=await SharedPreferences.getInstance();
     history.insert(0,'${DateTime.now().toLocal().toString().substring(0,16)} · Opened print dialog: $filename');
     history=history.take(20).toList();
     await prefs.setStringList('history',history);
     if(mounted)setState(()=>message='Sent to Android print dialog (not confirmed printed)');
   }catch(e){if(mounted)setState(()=>message='Print error: $e');}
 }
 @override void dispose(){scanGeneration++;ip.dispose();queue.dispose();servicePorts.dispose();super.dispose();}
 @override Widget build(BuildContext context){
   final style=Theme.of(context).textTheme;
   return Scaffold(appBar:AppBar(title:const Text('Digitus Print'),actions:[
     IconButton(tooltip:'Toggle theme',onPressed:widget.onTheme,icon:const Icon(Icons.contrast))
   ]),bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[
     NavigationDestination(icon:Icon(Icons.radar),label:'Discover'),
     NavigationDestination(icon:Icon(Icons.print_outlined),label:'Print'),
     NavigationDestination(icon:Icon(Icons.history),label:'History')
   ]),body:ListView(padding:const EdgeInsets.all(18),children:[
     if(tab==0)...[
       Card.outlined(child:Padding(
         padding:const EdgeInsets.all(12),
         child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           const Row(children:[Icon(Icons.system_update_alt),
             SizedBox(width:10),
             Expanded(child:Text('App updates',
               style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)))]),
           const SizedBox(height:6),
           if(updateMessage.isNotEmpty)Text(updateMessage),
           const SizedBox(height:8),
           OutlinedButton.icon(onPressed:checkingUpdate||downloadingUpdate?null:()=>checkForUpdates(),
             icon:const Icon(Icons.refresh),
             label:Text(checkingUpdate?'Checking...':'Check for updates')),
           if(availableUpdate!=null && newerVersion(
               availableUpdate!['version']?.toString()??'0',
               availableUpdate!['current']?.toString()??'0'))...[
             if(downloadingUpdate)const LinearProgressIndicator(),
             if(!updateDownloaded)FilledButton.icon(
               onPressed:downloadingUpdate?null:downloadUpdate,
               icon:const Icon(Icons.download),
               label:const Text('Download verified APK')),
             if(updateDownloaded)FilledButton.icon(
               onPressed:installUpdate,icon:const Icon(Icons.install_mobile),
               label:const Text('Install update')),
           ],
           const Text('Updates come from signed GitHub Releases. Android always asks you to approve installation.',
             style:TextStyle(fontSize:12)),
         ]))),
       const SizedBox(height:12),
       Text('Your printer',style:style.headlineMedium),
       const SizedBox(height:12),
       Card.filled(child:Padding(padding:const EdgeInsets.all(16),child:Column(
         crossAxisAlignment:CrossAxisAlignment.start,children:[
         const Row(children:[Icon(Icons.print,size:32),SizedBox(width:12),
           Expanded(child:Text('Canon PIXMA G2420',style:TextStyle(fontSize:20,fontWeight:FontWeight.w600)))]),
         const SizedBox(height:12),
         Text(hubInfo?.connectivityLabel??'Hub not identified yet'),
         Text('DIGITUS · ${ip.text.isEmpty?'Not configured':ip.text}',style:style.bodySmall),
         const SizedBox(height:4),
         Text('Print path: unverified · Queue: ${queue.text.isEmpty?'Not found':queue.text}',style:style.bodySmall),
         if(hubInfo!=null)Text('Hub firmware: ${hubInfo!.firmware??'Unknown'} · USB: ${hubInfo!.deviceStatus??'Unknown'}',style:style.bodySmall),
       ]))),
       const SizedBox(height:8),
       const Text('Discover LPR servers and attempt read-only queue detection. The hub and Canon model are not identifiable via standard LPR alone.'),
       const SizedBox(height:16),
       FilledButton.icon(onPressed:busy?null:discover,icon:const Icon(Icons.wifi_find),label:Text(busy?'Searching...':'Find my printer')),
       if(busy)TextButton.icon(onPressed:cancelDiscovery,icon:const Icon(Icons.close),label:const Text('Cancel search')),
       OutlinedButton.icon(onPressed:busy?null:checkSavedHub,icon:const Icon(Icons.refresh),label:const Text('Refresh hub status')),
       if(busy)LinearProgressIndicator(value:progress),
       for(final host in hosts)Card(child:Column(children:[
         ListTile(leading:const Icon(Icons.router),title:Text('Print server · $host'),
           subtitle:Text(queueMatches[host]?.isNotEmpty==true
             ? '${queueMatches[host]!.length} candidate queues found'
             : 'LPR port 515 accessible; queue not confirmed'),
           onTap:(){ip.text=host;save();}),
         for(final match in queueMatches[host]??<LprCandidate>[])
           ListTile(dense:true,leading:const Icon(Icons.print_outlined),
             title:Text('Possible queue: ${match.queue}'),
             subtitle:Text(match.evidence,maxLines:2,overflow:TextOverflow.ellipsis),
             trailing:const Icon(Icons.add_circle_outline),
             onTap:()async{
               ip.text=match.host;queue.text=match.queue;
               await save();
               if(mounted)setState(()=>message='Saved candidate queue ${match.queue}. Canon G2420 and physical printing remain unverified.');
             }),
       ])),
       if(ip.text.isNotEmpty)ListTile(
         leading:const Icon(Icons.link),
         title:const Text('Saved print server'),
         subtitle:Text('${ip.text} · ${queue.text.isEmpty?'Queue unknown':queue.text}'),
       ),
       Card.outlined(child:Padding(padding:const EdgeInsets.all(12),
         child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           const Text('USB hub connection diagnostics',
             style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
           const SizedBox(height:8),
           const Text('The DIGITUS hub has four physical USB sockets. TCP service ports (4660 / 3240 / 515) are network endpoints, not physical USB socket numbers.'),
           const SizedBox(height:8),
           const Text('Physical USB socket (informational until vendor protocol is decoded)'),
           DropdownButton<int>(
             value:selectedUsbSocket,
             items:List.generate(UsbPortDiagnostics.physicalPortCount,
               (i)=>DropdownMenuItem(value:i+1,child:Text('USB socket ${i+1}'))),
             onChanged:(value)async{
               if(value==null)return;
               setState(()=>selectedUsbSocket=value);
               final prefs=await SharedPreferences.getInstance();
               await prefs.setInt('usbSocket',value);
             }),
           const Text('Selecting a socket does not route print jobs yet.',
             style:TextStyle(fontSize:12)),
           const SizedBox(height:8),
           TextField(controller:servicePorts,
             keyboardType:TextInputType.text,
             decoration:const InputDecoration(
               border:OutlineInputBorder(),
               labelText:'TCP ports to check',
               helperText:'Comma-separated; default 4660,3240,515 (max 16)')),
           const SizedBox(height:8),
           OutlinedButton.icon(onPressed:probingServices?null:checkUsbNetworkPorts,
             icon:const Icon(Icons.lan),
             label:Text(probingServices?'Checking ports...':'Check network services')),
           for(final port in networkServices)
             ListTile(dense:true,
               leading:Icon(port.open?Icons.check_circle_outline:Icons.cancel_outlined,
                 color:port.open?Colors.green:null),
               title:Text('TCP ${port.port}: ${port.open?'Open':'No connection'}'),
               subtitle:Text(port.description)),
           const Text('Open TCP 4660 may match the NU V1.25 traffic captured on Windows. It is not a functional USB-over-IP connection until the vendor handshake is decoded.',
             style:TextStyle(fontSize:12)),
         ]))),
       const SizedBox(height:12),
       Card.outlined(child:Padding(
         padding:const EdgeInsets.all(12),
         child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           const Text('DA-70251 UDP discovery',
             style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
           const SizedBox(height:6),
           const Text('Listen for actual DCP$ broadcasts from the Windows-era hub; no attach commands are sent.'),
           OutlinedButton.icon(
             onPressed:dcpListening?null:listenDcp,
             icon:const Icon(Icons.radar),
             label:Text(dcpListening?'Listening...':'Listen for USB hub')),
           if(dcpDiagnostic!=null)...[
             Text(dcpDiagnostic!.detail),
             if(dcpDiagnostic!.info!=null)...[
               Text('Hub: ${dcpDiagnostic!.info!.name}'),
               Text('MAC: ${dcpDiagnostic!.info!.mac}'),
               Text('USB sockets: ${dcpDiagnostic!.info!.physicalPortCount}'),
               if(dcpDiagnostic!.info!.reportedDevice!=null)
                 Text('USB descriptor: ${dcpDiagnostic!.info!.reportedDevice}'),
               if(dcpDiagnostic!.info!.manufacturer!=null)
                 Text('Manufacturer: ${dcpDiagnostic!.info!.manufacturer}'),
               if(dcpDiagnostic!.info!.serial!=null)
                 Text('USB serial: ${dcpDiagnostic!.info!.serial}'),
             ]
           ]
         ]))),
       const SizedBox(height:12),
       Card.outlined(child:Padding(
         padding:const EdgeInsets.all(12),
         child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           const Row(children:[Icon(Icons.usb),SizedBox(width:8),
             Expanded(child:Text('NU V1.25 direct USB research',
               style:TextStyle(fontSize:16,fontWeight:FontWeight.w600)))]),
           const SizedBox(height:6),
           const Text('Windows capture identified TCP 4660 and an UNT\$ packet signature. Check whether the hub accepts a passive connection. This does not send discovery commands or claim any USB socket.'),
           OutlinedButton.icon(
             onPressed:vendorProbeRunning?null:inspectNuVendor,
             icon:const Icon(Icons.network_check),
             label:Text(vendorProbeRunning?'Observing...':'Observe vendor USB service')),
           if(vendorUsbDiagnostic!=null)
             ListTile(
               leading:Icon(vendorUsbDiagnostic!.connected
                 ? Icons.link:Icons.link_off),
               title:Text(vendorUsbDiagnostic!.connected
                 ? 'TCP 4660 reachable':'TCP 4660 unavailable'),
               subtitle:Text(vendorUsbDiagnostic!.detail),
             ),
           const Text('Native vendor USB attach, port enumeration and USB transfers still require decoding a capture of Windows Search → Connect → Disconnect.',
             style:TextStyle(fontSize:12)),
         ]))),
       const SizedBox(height:12),
       Card.outlined(child:Padding(
         padding:const EdgeInsets.all(12),
         child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           const Text('DA-70251 native USB discovery',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
           const SizedBox(height:6),
           const Text('Listen for hub DCP\$ announcements on UDP 52340. No USB commands or device claims are transmitted.'),
           OutlinedButton.icon(
             onPressed:listeningDcp?null:listenForDcp,
             icon:const Icon(Icons.sensors),
             label:Text(listeningDcp?'Listening...':'Listen for USB devices')),
           if(dcpResult!=null)Text(dcpResult!.detail),
           if(dcpResult?.info!=null)...[
             ListTile(title:Text(dcpResult!.info!.name),
               subtitle:Text('MAC ${dcpResult!.info!.mac} · ${dcpResult!.info!.physicalPortCount} USB sockets')),
             if(dcpResult!.info!.reportedDevice!=null)
               ListTile(title:Text('USB descriptor: ${dcpResult!.info!.reportedDevice}'),
                 subtitle:Text('Manufacturer: ${dcpResult!.info!.manufacturer??'Unknown'}')),
           ],
           const Text('Discovery alone is not USB attachment or print support.',style:TextStyle(fontSize:12)),
         ]))),
       const SizedBox(height:12),
       ExpansionTile(
         title:const Text('USB-over-IP research diagnostics'),
         subtitle:const Text('Safe protocol detection · no USB attachment'),
         children:[
           const Padding(padding:EdgeInsets.all(12),
             child:Text('NU V1.25 may use a proprietary USB-sharing protocol. This test checks only the standard Linux USB/IP device-list request on TCP/3240. It never connects to or claims the printer.')),
           OutlinedButton.icon(onPressed:busy?null:inspectNativeUsbIp,
             icon:const Icon(Icons.usb),label:const Text('Check standard USB/IP')),
           if(usbIpDiagnostic!=null)Padding(padding:const EdgeInsets.all(8),
             child:Text(usbIpDiagnostic!.detail)),
           if(usbIpDiagnostic?.supported==true)
             for(final dev in usbIpDiagnostic!.devices)
               ListTile(title:Text('USB ${dev.identity}'),
                 subtitle:Text('Bus ${dev.busId} · ${dev.interfaceCount} interface(s)')),
           const Padding(padding:EdgeInsets.all(12),
             child:Text('A negative result does NOT mean that NU V1.25 cannot connect. It only means the standard USB/IP protocol was not confirmed.')),
         ],
       ),
       ExpansionTile(
         title:const Text('Advanced connection settings'),
         subtitle:const Text('Manual IP, LPR queue and diagnostics'),
         initiallyExpanded:showAdvanced,
         onExpansionChanged:(v)=>setState(()=>showAdvanced=v),
         children:[
           TextField(controller:ip,decoration:const InputDecoration(
             border:OutlineInputBorder(),labelText:'Hub IP address')),
           const SizedBox(height:12),
           TextField(controller:queue,decoration:const InputDecoration(
             border:OutlineInputBorder(),labelText:'LPR queue name',
             helperText:'Required only when discovery cannot identify a queue')),
           OutlinedButton.icon(onPressed:save,icon:const Icon(Icons.save),label:const Text('Save connection')),
           OutlinedButton.icon(onPressed:inspectQueue,icon:const Icon(Icons.fact_check_outlined),label:const Text('Inspect queue')),
         ],
       ),
       const SizedBox(height:12),
       const Card(child:Padding(padding:EdgeInsets.all(14),child:Text(
         'Hub status confirms a USB connection only. Printing on the Canon G2420 remains experimental until a physical test page succeeds.'
       ))),
     ]else if(tab==1)...[
       Text('Print a document',style:style.headlineMedium),
       Card.filled(child:ListTile(leading:const Icon(Icons.print),title:const Text('Canon PIXMA G2420'),
          subtitle:Text('DIGITUS · ${ip.text.isEmpty?'Not connected':ip.text} · ${queue.text.isEmpty?'Queue unknown':queue.text}'))),
       const Text('PDF, PNG, JPEG, TXT'),
       const SizedBox(height:16),
       FilledButton.icon(onPressed:pick,icon:const Icon(Icons.folder_open),label:const Text('Choose file')),
       OutlinedButton.icon(onPressed:createCanonTestPage,
         icon:const Icon(Icons.science),label:const Text('Prepare one-page printer test')),
       if(filename.isNotEmpty)ListTile(leading:const Icon(Icons.description),title:Text(filename)),
       Row(children:[
         Expanded(child:DropdownButtonFormField<String>(initialValue:paper,
           decoration:const InputDecoration(labelText:'Page size'),
           items:const[DropdownMenuItem(value:'A4',child:Text('A4')),DropdownMenuItem(value:'Letter',child:Text('Letter'))],
           onChanged:(v){if(v!=null)setState(()=>paper=v);})),
         Expanded(child:SwitchListTile(title:const Text('Landscape'),value:landscape,
           onChanged:(v)=>setState(()=>landscape=v)))
       ]),
       const Text('Page size and orientation apply when preparing newly selected images and text. For existing PDFs, the original layout is preserved.'),
       if(pdfBytes!=null)OutlinedButton.icon(
         onPressed:()=>setState(()=>showPreview=!showPreview),
         icon:Icon(showPreview?Icons.visibility_off:Icons.preview),
         label:Text(showPreview?'Hide preview':'Show document preview')),
       if(pdfBytes!=null && showPreview)SizedBox(height:320,child:PdfPreview(
         build:(_)=>pdfBytes!,allowPrinting:false,allowSharing:false,
         canChangePageFormat:false,canChangeOrientation:false)),
       const SizedBox(height:12),
       FilledButton.icon(onPressed:pdfBytes==null?null:printFile,icon:const Icon(Icons.print),label:const Text('Open Android print dialog')),
       const SizedBox(height:8),
       const SizedBox(height:12),
       const Divider(),
       Text('Native Canon test print',style:style.titleLarge),
       const SizedBox(height:8),
       const Text('Experimental: converts ONLY PAGE 1 to Canon G2020-series IVEC/PWG raster and sends it to your DIGITUS LPR queue. G2420 compatibility and hub forwarding are not yet verified; ink and paper may be consumed. No Windows or server required.'),
       SwitchListTile(title:const Text('Grayscale'),subtitle:const Text('Canon normal-quality A4'),value:canonGrayscale,
         onChanged:canonBusy?null:(value)=>setState(()=>canonGrayscale=value)),
       SwitchListTile(
         title:const Text('Compatibility: send raster data first'),
         subtitle:const Text('For older LPR servers that close after the control-file header. OFF uses RFC standard control-first. Does not automatically retry.'),
         value:canonDataFirst,
         onChanged:canonBusy?null:(value)async{
           setState(()=>canonDataFirst=value);
           final prefs=await SharedPreferences.getInstance();
           await prefs.setBool('canonDataFirst',value);
         }),
       SwitchListTile(
         title:const Text('Advanced: RFC1179 reserved source port'),
         subtitle:const Text('Tries local TCP ports 721-731. Usually denied for Android apps. This does NOT use root, never falls back, and never retries the print job.'),
         value:canonReservedPort,
         onChanged:canonBusy?null:(value)async{
           setState(()=>canonReservedPort=value);
           final prefs=await SharedPreferences.getInstance();
           await prefs.setBool('canonReservedPort',value);
         }),
       CheckboxListTile(
         title:const Text('I understand this is an unverified G2020-family test'),
         value:canonConsent,onChanged:canonBusy?null:(value)=>setState(()=>canonConsent=value??false),
       ),
       FilledButton.icon(
         onPressed:pdfBytes!=null && canonConsent && !canonBusy?testCanonNative:null,
         icon:const Icon(Icons.science_outlined),
         label:Text(canonBusy?'Preparing and sending raster...':'Send 1-page Canon IVEC test'),
       ),
       const Text('If the hub closes after queue ACK, try Data First manually. This is a transport experiment and cannot verify Canon G2420 printer-language compatibility. Never repeatedly resend when the output status is uncertain.'),

     ]else...[
       Text('Activity history',style:style.headlineMedium),
       const Text('Logs include print-dialog launches and LPR acknowledgements, not verified physical output.'),
       for(final item in history)ListTile(leading:const Icon(Icons.description_outlined),title:Text(item)),
       if(history.isEmpty)const ListTile(title:Text('No activity yet')),
     ],
     const SizedBox(height:18),
     Text(message,style:style.bodySmall),
   ]));
 }
}
