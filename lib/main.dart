import 'dart:typed_data';
import 'services/hub_discovery.dart';
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
 final ip=TextEditingController(),queue=TextEditingController();
 int tab=0; bool busy=false,landscape=false,canonConsent=false,canonBusy=false,canonGrayscale=false,showAdvanced=false,showPreview=false;
 double progress=0;
 String message='Ready to scan',paper='A4';
 Uint8List? pdfBytes; String filename='';
 List<String> hosts=[],history=[];
 final Map<String,List<LprCandidate>> queueMatches={};
 @override void initState(){super.initState();load();}
 Future<void> load() async {
   final prefs=await SharedPreferences.getInstance();
   if(!mounted)return;
   setState((){
     ip.text=prefs.getString('ip')??'';
     queue.text=prefs.getString('queue')??'';
     history=prefs.getStringList('history')??[];
   });
 }
 Future<void> save() async {
   final prefs=await SharedPreferences.getInstance();
   await prefs.setString('ip',ip.text.trim());
   await prefs.setString('queue',queue.text.trim());
   if(mounted)setState(()=>message='Connection saved');
 }
 Future<void> discover() async {
   if(busy)return;
   setState((){busy=true;hosts=[];queueMatches.clear();progress=0;
     message='Searching your local network for print servers...';});
   try {
     final prefixes=await HubDiscovery.localPrefixes();
     if(prefixes.isEmpty){
       setState(()=>message='No private LAN address found. Connect to your Wi-Fi.');
       return;
     }
     final targets=<String>[];
     for(final prefix in prefixes){
       for(int x=1;x<=254;x++){targets.add('$prefix.$x');}
     }
     final found=<String>[];
     for(var i=0;i<targets.length;i+=64){
       final group=targets.skip(i).take(64);
       final checks=await Future.wait(group.map((host)async{
         return await HubDiscovery.hasLpr(host)?host:null;
       }));
       found.addAll(checks.whereType<String>());
       if(!mounted)return;
       setState((){
         hosts=List.of(found);
         progress=((i+64).clamp(0,targets.length))/targets.length;
       });
     }
     if(found.isEmpty){
       if(mounted)setState(()=>message='No LPR hub found. Check the network and printer hub.');
       return;
     }
     if(mounted)setState(()=>message='Found ${found.length} LPR endpoint(s). Checking queues safely...');
     // Old print servers may reject queue-status requests; never fabricate a queue.
     for(final host in found.take(6)){
       final matches=await HubDiscovery.probeQueues(host);
       if(!mounted)return;
       setState(()=>queueMatches[host]=matches);
     }
     final confirmed=<LprCandidate>[];
     for(final matches in queueMatches.values){confirmed.addAll(matches);}
     if(confirmed.length==1 && found.length==1){
       ip.text=confirmed.single.host;
       queue.text=confirmed.single.queue;
       await save();
       if(mounted)setState(()=>message='Saved one possible LPR queue automatically. Print output and Canon model are not verified.');
     }else if(mounted){
       setState(()=>message=confirmed.isEmpty
         ? 'Found ${found.length} LPR server(s), but none disclosed a known queue. Choose a hub; its queue may require one-time setup.'
         : 'Found ${confirmed.length} possible queues. Select the correct entry to connect.');
     }
   }catch(e){if(mounted)setState(()=>message='Discovery error: $e');}
   finally {if(mounted)setState(()=>busy=false);}
 }
 Future<void> inspectQueue() async {
   final host = ip.text.trim(), q = queue.text.trim();
   if(host.isEmpty || q.isEmpty) {setState(()=>message='Enter or discover a hub and provide its LPR queue name');return;}
   setState(()=>message='Inspecting LPR queue...');
   try {
     final response = await const LprTransport().queryQueue(host:host,queue:q);
     if(mounted)setState(()=>message=response.trim().isEmpty
       ? 'LPD replied with an empty queue status (printer compatibility not verified)'
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
 Future<void> testCanonNative() async {
   if (pdfBytes==null || !canonConsent || canonBusy) return;
   if (ip.text.trim().isEmpty || queue.text.trim().isEmpty) {
     setState(()=>message='First select your hub and configure its exact LPR queue.');return;
   }
   setState((){canonBusy=true;message='Converting first PDF page to Canon G2020-series IVEC raster on Android...';});
   try {
     final result=await const MethodChannel('digitus_print/canon').invokeMethod<String>(
       'experimentalPrint',<String,dynamic>{
         'pdf':pdfBytes,'host':ip.text.trim(),'queue':queue.text.trim(),
         'gray':canonGrayscale,'approved':canonConsent,
       });
     history.insert(0,'${DateTime.now().toLocal().toString().substring(0,16)} · Canon LPR ACK (output unverified): $filename');
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
 @override void dispose(){ip.dispose();queue.dispose();super.dispose();}
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
       Text('Discover your print hub',style:style.headlineMedium),
       const SizedBox(height:8),
       const Text('Discover LPR servers and attempt read-only queue detection. The hub and Canon model are not identifiable via standard LPR alone.'),
       const SizedBox(height:16),
       FilledButton.icon(onPressed:busy?null:discover,icon:const Icon(Icons.wifi_find),label:Text(busy?'Searching...':'Discover printers')),
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
         'Canon PIXMA G2420 requires Canon raster printer commands. A detected LPR hub alone cannot print raw PDFs or photos. Android printing requires a compatible print service or bridge.'
       ))),
     ]else if(tab==1)...[
       Text('Print a document',style:style.headlineMedium),
       const Text('PDF, PNG, JPEG, TXT'),
       const SizedBox(height:16),
       FilledButton.icon(onPressed:pick,icon:const Icon(Icons.folder_open),label:const Text('Choose file')),
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
       CheckboxListTile(
         title:const Text('I understand this is an unverified G2020-family test'),
         value:canonConsent,onChanged:canonBusy?null:(value)=>setState(()=>canonConsent=value??false),
       ),
       FilledButton.icon(
         onPressed:pdfBytes!=null && canonConsent && !canonBusy?testCanonNative:null,
         icon:const Icon(Icons.science_outlined),
         label:Text(canonBusy?'Preparing and sending raster...':'Send 1-page Canon IVEC test'),
       ),
       const Text('Hub acknowledgement only: the app cannot yet confirm physical page output or read G2420 ink/error status over LPR.'),

     ]else...[
       Text('Activity history',style:style.headlineMedium),
       const Text('Records print-dialog launches, not verified output.'),
       for(final item in history)ListTile(leading:const Icon(Icons.description_outlined),title:Text(item)),
       if(history.isEmpty)const ListTile(title:Text('No activity yet')),
     ],
     const SizedBox(height:18),
     Text(message,style:style.bodySmall),
   ]));
 }
}
