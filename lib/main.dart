import 'dart:typed_data';
import 'services/hub_web_probe.dart';
import 'services/usbip_discovery.dart';
import 'services/vendor_usb_discovery.dart';
import 'services/dcp_discovery.dart';
import 'services/nu_session.dart';
import 'services/nu_canon_connection.dart';
import 'services/usb_port_diagnostics.dart';
import 'package:flutter/services.dart';

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
 final ip=TextEditingController(),
   servicePorts=TextEditingController(text:'4660');
 int selectedUsbSocket=1;
 bool probingServices=false;
 bool checkingUpdate=false,downloadingUpdate=false,updateDownloaded=false;
 String updateMessage='';
 Map<String,dynamic>? availableUpdate;
 List<NetworkServicePort> networkServices=[];
 int tab=0; bool busy=false,landscape=false,canonConsent=false,canonBusy=false,canonGrayscale=false,showAdvanced=false,showPreview=false;
 double progress=0;
 String message='Ready to scan',paper='A4';
 HubSnapshot? hubInfo;
 UsbIpResult? usbIpDiagnostic;
 NuVendorObservation? vendorUsbDiagnostic;
 DcpListenResult? dcpDiagnostic;
 bool dcpListening=false;
 final NuCanonConnection nuConnection=NuCanonConnection();
 bool nuConnectRunning=false;
 bool nuPrinterIdRunning=false;
 bool nuExperimentalPrint=false;
 String nuPrinterIdMessage='';
 String nuConnectionMessage='Not connected to Canon USB device';
 NuHelloResult? nuGreetingResult;
 bool nuGreetingRunning=false;
 bool vendorProbeRunning=false;
 Uint8List? pdfBytes; String filename='';
 List<String> history=[];
 @override void initState(){super.initState();load();}
 Future<void> load() async {
   final prefs=await SharedPreferences.getInstance();
   if(!mounted)return;
   setState((){
     ip.text=prefs.getString('ip')??'192.168.0.74';
     servicePorts.text=prefs.getString('usbIpTcpPorts')??'4660';
     selectedUsbSocket=(prefs.getInt('usbSocket')??1).clamp(1,4);
     history=prefs.getStringList('history')??[];
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
   await prefs.setString('usbIpTcpPorts',servicePorts.text.trim());
   await prefs.setInt('usbSocket',selectedUsbSocket);
   if(mounted)setState(()=>message='NU hub address saved');
 }
 Future<void> checkSavedHub() async {
   final host=ip.text.trim();
   if(host.isEmpty)return;
   final details=await const HubWebProbe().inspect(host);
   if(!mounted || ip.text.trim()!=host)return;
   setState((){
     hubInfo=details;
     if(details!=null)message='USB sharing hub found at $host. Native NU printing requires a verified print test.';
   });
 }
 void cancelDiscovery() {
   setState((){busy=false;message='Discovery cancelled';});
 }
 Future<void> discover() async {
   if(busy)return;
   final host=ip.text.trim();
   setState((){
     busy=true;
     progress=0;
     message='Discovering DIGITUS NU hub over UDP DCP...';
   });
   try {
     final result=await const DcpDiscovery().discover(expectedHub:host);
     if(!mounted||host!=ip.text.trim())return;
     setState((){
       dcpDiagnostic=result;
       progress=1;
       message=result.info==null
         ?result.detail
         :'DIGITUS NU hub: ${result.info!.name}; Canon: '
           '${result.info!.reportedDevice??'not reported'}';
     });
   } catch(e) {
     if(mounted)setState(()=>message='NU discovery failed: $e');
   } finally {
     if(mounted)setState(()=>busy=false);
   }
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
 Future<void> listenDcp() async {
   if(dcpListening)return;
   final host=ip.text.trim();
   setState((){
     dcpListening=true;
     dcpDiagnostic=null;
     message='Sending captured DA-70251 UDP discovery request...';
   });
   try{
     final result=await const DcpDiscovery().discover(expectedHub:host);
     if(!mounted||host!=ip.text.trim())return;
     setState((){
       dcpDiagnostic=result;
       message=result.detail;
     });
   }catch(e){if(mounted)setState(()=>message='DCP listening failed: $e');}
   finally{if(mounted)setState(()=>dcpListening=false);}
 }
 Future<void> inspectNuGreeting() async {
   if(nuGreetingRunning)return;
   final host=ip.text.trim();
   setState((){
     nuGreetingRunning=true;
     nuGreetingResult=null;
     message='Testing captured TCP 4660 session greeting...';
   });
   try{
     final result=await const NuSessionDiagnostics().greeting(host);
     if(!mounted||host!=ip.text.trim())return;
     setState((){
       nuGreetingResult=result;
       message=result.detail;
     });
   }catch(e){if(mounted)setState(()=>message='UNT session greeting failed: $e');}
   finally{if(mounted)setState(()=>nuGreetingRunning=false);}
 }
 Future<void> connectCanonNu() async {
   if(nuConnectRunning||nuConnection.isConnected)return;
   setState((){
     nuConnectRunning=true;
     nuConnectionMessage='Opening captured NU session and reading Canon USB descriptor...';
   });
   try{
     final detail=await nuConnection.connect(ip.text.trim());
     if(mounted)setState((){
       nuConnectionMessage=detail;
       message=detail;
     });
   }catch(e){
     if(mounted)setState((){
       nuConnectionMessage='USB descriptor connection failed: $e';
       message=nuConnectionMessage;
     });
   }finally{
     if(mounted)setState(()=>nuConnectRunning=false);
   }
 }
 Future<void> readCanonPrinterId() async {
   if(nuPrinterIdRunning||!nuConnection.isConnected)return;
   setState((){
     nuPrinterIdRunning=true;
     nuPrinterIdMessage='Requesting USB printer-class IEEE 1284 ID...';
   });
   try {
     final id=await nuConnection.readPrinterId();
     if(mounted)setState((){
       nuPrinterIdMessage=id;
       message='Canon printer-class response verified over NU TCP 4660.';
     });
   } catch(e) {
     if(mounted)setState((){
       nuPrinterIdMessage='Printer ID request failed: $e';
       message=nuPrinterIdMessage;
     });
   } finally {
     if(mounted)setState(()=>nuPrinterIdRunning=false);
   }
 }
 Future<void> disconnectCanonNu() async {
   await nuConnection.disconnect();
   if(mounted)setState((){
     nuPrinterIdMessage='';
     nuConnectionMessage='NU TCP session closed. Vendor release opcode unverified.';
     message=nuConnectionMessage;
   });
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
         pw.Text('A NU bulk transfer acknowledgement alone does not prove printing.'),
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
   if(pdfBytes==null || !canonConsent || canonBusy || !nuExperimentalPrint)return;
   if(!nuConnection.isConnected || nuConnection.ieee1284DeviceId==null){
     setState(()=>message='Connect NU and read Canon printer-class ID first.');
     return;
   }
   setState((){
     canonBusy=true;
     message='Rendering first PDF page into Canon IVEC raster...';
   });
   try {
     final raster=await const MethodChannel('digitus_print/canon')
       .invokeMethod<Uint8List>('prepareRaster',{
         'pdf':pdfBytes,'gray':canonGrayscale,'approved':true,
       });
     if(raster==null||raster.isEmpty)throw StateError('No raster generated');
     if(!mounted)return;
     setState(()=>message='Experimental NU bulk OUT: sending ${raster.length} bytes; no automatic retry...');
     final result=await nuConnection.experimentalNuPrint(raster);
     history.insert(0,'${DateTime.now().toLocal().toString().substring(0,16)} · NU bulk test: ${raster.length} bytes; physical output unverified');
     history=history.take(20).toList();
     final prefs=await SharedPreferences.getInstance();
     await prefs.setStringList('history',history);
     if(mounted)setState(()=>message=result);
   }catch(e){
     if(mounted)setState(()=>message='NU print attempt failed (do not blindly retry): $e');
   }finally{
     if(mounted)setState(()=>canonBusy=false);
   }
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
 @override void dispose(){nuConnection.disconnect();ip.dispose();servicePorts.dispose();super.dispose();}
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
         Text('Print path: experimental native NU · TCP 4660',style:style.bodySmall),
         if(hubInfo!=null)Text('Hub firmware: ${hubInfo!.firmware??'Unknown'} · USB: ${hubInfo!.deviceStatus??'Unknown'}',style:style.bodySmall),
       ]))),
       const SizedBox(height:8),
       const Text('Discover the DIGITUS NU hub directly using its DCP protocol.'),
       const SizedBox(height:16),
       FilledButton.icon(onPressed:busy?null:discover,icon:const Icon(Icons.wifi_find),label:Text(busy?'Searching...':'Find my printer')),
       if(busy)TextButton.icon(onPressed:cancelDiscovery,icon:const Icon(Icons.close),label:const Text('Cancel search')),
       OutlinedButton.icon(onPressed:busy?null:checkSavedHub,icon:const Icon(Icons.refresh),label:const Text('Refresh hub status')),
       if(busy)LinearProgressIndicator(value:progress),
       if(ip.text.isNotEmpty)ListTile(
         leading:const Icon(Icons.usb),
         title:const Text('Native NU print server'),
         subtitle:Text('${ip.text} · TCP 4660'),
       ),
       Card.outlined(child:Padding(padding:const EdgeInsets.all(12),
         child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           const Text('USB hub connection diagnostics',
             style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
           const SizedBox(height:8),
           const Text('DIGITUS has four physical USB sockets. TCP 4660 is the native NU protocol, not a physical USB socket.'),
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
           const Text('TCP 4660 is the native NU transport. The hub, Canon descriptors and printer ID have been verified live.',
             style:TextStyle(fontSize:12)),
         ]))),
       const SizedBox(height:12),
       Card.outlined(child:Padding(
         padding:const EdgeInsets.all(12),
         child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           const Text('DA-70251 UDP discovery',
             style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
           const SizedBox(height:6),
           const Text('Send the exact 40-byte DCP discovery request from the Windows capture. No printer is claimed.'),
           OutlinedButton.icon(
             onPressed:dcpListening?null:listenDcp,
             icon:const Icon(Icons.radar),
             label:Text(dcpListening?'Discovering...':'Discover USB hub and devices')),
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
           const Text('NU V1.25 TCP handshake',
             style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
           const Text('Sends the 116-byte session greeting captured from Windows '
             'and checks the 100-byte UNT response. Does NOT attach the Canon or print.'),
           OutlinedButton.icon(
             onPressed:nuGreetingRunning?null:inspectNuGreeting,
             icon:const Icon(Icons.handshake),
             label:Text(nuGreetingRunning?'Testing...':'Test vendor handshake')),
           if(nuGreetingResult!=null)...[
             Text(nuGreetingResult!.accepted
                 ? 'Hub accepted session greeting'
                 : 'Handshake not confirmed'),
             Text(nuGreetingResult!.detail),
           ],
         ]))),
       const SizedBox(height:12),
       const SizedBox(height:12),
       Card.outlined(child:Padding(padding:const EdgeInsets.all(12),
         child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           const Text('Experimental Canon USB connection',
             style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
           const SizedBox(height:6),
           const Text('Uses the captured NU greeting and one READ-ONLY USB '
             'GET_DESCRIPTOR request. A verified Canon 04A9:183A reply confirms '
             'USB communication, NOT an exclusive device claim or printing. '
             'Close the Windows USB Server utility before testing.'),
           const SizedBox(height:8),
           Wrap(spacing:8,children:[
             FilledButton.icon(
               onPressed:nuConnectRunning||nuConnection.isConnected
                 ?null:connectCanonNu,
               icon:const Icon(Icons.usb),
               label:Text(nuConnectRunning?'Connecting...':
                 'Connect and verify Canon USB')),
             OutlinedButton.icon(
               onPressed:nuConnectRunning||!nuConnection.isConnected
                 ?null:disconnectCanonNu,
               icon:const Icon(Icons.link_off),
               label:const Text('Disconnect NU session')),
           ]),
           const SizedBox(height:8),
           OutlinedButton.icon(
             onPressed:nuPrinterIdRunning||!nuConnection.isConnected
               ?null:readCanonPrinterId,
             icon:const Icon(Icons.badge_outlined),
             label:Text(nuPrinterIdRunning?'Reading ID...':
               'Read Canon printer-class ID')),
           if(nuPrinterIdMessage.isNotEmpty)
             SelectableText(nuPrinterIdMessage),
           Text(nuConnectionMessage),
           if(nuConnection.printerInterface!=null)...[
             Text('USB printer interface: ${nuConnection.printerInterface!.number}'),
             Text('Bulk OUT: ${nuConnection.printerInterface!.bulkOut!.hexAddress}'),
             const Text('Bulk endpoint detected from the Canon USB configuration; '
               'native print transfers require separate NU framing validation.',
               style:TextStyle(fontSize:12)),
           ],
           if(nuConnection.isConnected)
             const Text('USB descriptor verified. Experimental NU bulk OUT '
               'printing is available from the Print tab after reading '
               'the Canon printer-class ID.',
               style:TextStyle(fontSize:12)),
         ]))),
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
         title:const Text('Advanced NU connection settings'),
         subtitle:const Text('Hub IP address and diagnostics'),
         initiallyExpanded:showAdvanced,
         onExpansionChanged:(v)=>setState(()=>showAdvanced=v),
         children:[
           TextField(controller:ip,decoration:const InputDecoration(
             border:OutlineInputBorder(),labelText:'Hub IP address')),
           const SizedBox(height:12),
           OutlinedButton.icon(onPressed:save,icon:const Icon(Icons.save),label:const Text('Save connection')),
         ],
       ),
       const SizedBox(height:12),
       const Card(child:Padding(padding:EdgeInsets.all(14),child:Text(
         'Hub status confirms a USB connection only. Printing on the Canon G2420 remains experimental until a physical test page succeeds.'
       ))),
     ]else if(tab==1)...[
       Text('Print a document',style:style.headlineMedium),
       Card.filled(child:ListTile(leading:const Icon(Icons.print),title:const Text('Canon PIXMA G2420'),
          subtitle:Text('DIGITUS · ${ip.text.isEmpty?'Not connected':ip.text} · NU TCP 4660'))),
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
       Text('Native NU Canon test print',style:style.titleLarge),
       const SizedBox(height:8),
       const Text('Experimental direct USB-over-IP printing on TCP 4660. '
         'No LPR or Windows. The captured NU bulk framing is not fully '
         'validated and a failed attempt may leave output status uncertain. '
         'Do not repeat a job without checking the printer.'),
       SwitchListTile(
         title:const Text('Enable experimental NU printing'),
         subtitle:const Text('Opt-in only; requires an open verified NU session '
           'and Canon printer-class ID (IVEC).'),
         value:nuExperimentalPrint,
         onChanged:canonBusy?null:(value)=>setState(()=>nuExperimentalPrint=value)),
       SwitchListTile(title:const Text('Grayscale'),
         subtitle:const Text('Canon G2020-family IVEC raster, A4 normal quality'),
         value:canonGrayscale,
         onChanged:canonBusy?null:(v)=>setState(()=>canonGrayscale=v)),
       CheckboxListTile(
         title:const Text('I accept an unverified NU bulk-transfer print test'),
         value:canonConsent,
         onChanged:canonBusy?null:(v)=>setState(()=>canonConsent=v??false)),
       FilledButton.icon(
         onPressed:pdfBytes!=null && canonConsent && nuExperimentalPrint &&
           nuConnection.isConnected &&
           nuConnection.ieee1284DeviceId!=null && !canonBusy
             ?testCanonNative:null,
         icon:const Icon(Icons.print),
         label:Text(canonBusy?'Sending experimental NU raster...':
           'Test 1-page NU printing')),
       const Text('Requires Connect and verify Canon USB, then Read Canon '
         'printer-class ID on the Discover tab. USB completion does not '
         'prove a page printed. Never automatically retry.'),

     ]else...[
       Text('Activity history',style:style.headlineMedium),
       const Text('NU bulk completions and Android print-dialog launches do not confirm physical output.'),
       for(final item in history)ListTile(leading:const Icon(Icons.description_outlined),title:Text(item)),
       if(history.isEmpty)const ListTile(title:Text('No activity yet')),
     ],
     const SizedBox(height:18),
     Text(message,style:style.bodySmall),
   ]));
 }
}
