import 'dart:io';
import 'dart:typed_data';
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
 int tab=0; bool busy=false,landscape=false;
 double progress=0;
 String message='Ready to scan',paper='A4';
 Uint8List? pdfBytes; String filename='';
 List<String> hosts=[],history=[];
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
   setState((){busy=true;hosts=[];progress=0;message='Scanning for LPR servers...';});
   try{
     final nics=await NetworkInterface.list(type:InternetAddressType.IPv4,includeLoopback:false);
     final prefixes=<String>{};
     for(final nic in nics){for(final addr in nic.addresses){
       final s=addr.address.split('.');
       if(s.length==4 && s[0]!='127' && s[0]!='169') prefixes.add('${s[0]}.${s[1]}.${s[2]}');
     }}
     final targets=<String>[];
     for(final prefix in prefixes.take(2)){for(int x=1;x<=254;x++){targets.add('$prefix.$x');}}
     for(var i=0;i<targets.length;i+=24){
       final found=await Future.wait(targets.skip(i).take(24).map((host)async{
         try{final socket=await Socket.connect(host,515,timeout:const Duration(milliseconds:500));
           socket.destroy();return host;
         }catch(_){return null;}
       }));
       if(!mounted)return;
       setState((){
         hosts.addAll(found.whereType<String>());
         progress=(i+24).clamp(0,targets.length)/ (targets.isEmpty?1:targets.length);
       });
     }
     if(mounted)setState(()=>message=hosts.isEmpty?'No LPR service found; check Wi-Fi and hub power':'Found ${hosts.length} possible LPR server(s)');
   }catch(e){if(mounted)setState(()=>message='Discovery error: $e');}
   finally{if(mounted)setState(()=>busy=false);}
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
     final result=await FilePicker.platform.pickFiles(type:FileType.custom,
       allowedExtensions:['pdf','jpg','jpeg','png','txt'],withData:true);
     if(result==null)return;
     final f=result.files.first;
     final bytes=f.bytes??(f.path!=null?await File(f.path!).readAsBytes():null);
     if(bytes==null)throw Exception('Cannot read file');
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
     if(mounted)setState((){filename=f.name;tab=1;message='Prepared: $filename';});
   }catch(e){if(mounted)setState(()=>message='File error: $e');}
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
       const Text('Scan your current Wi-Fi for devices accepting LPR on port 515. Results are candidates, not verified DIGITUS devices.'),
       const SizedBox(height:16),
       FilledButton.icon(onPressed:busy?null:discover,icon:const Icon(Icons.wifi_find),label:Text(busy?'Scanning...':'Find print hubs')),
       if(busy)LinearProgressIndicator(value:progress),
       for(final host in hosts)Card(child:ListTile(leading:const Icon(Icons.router),title:Text(host),
         subtitle:const Text('LPR port 515 accessible'),trailing:const Icon(Icons.chevron_right),
         onTap:(){ip.text=host;save();})),
       const SizedBox(height:16),
       TextField(controller:ip,decoration:const InputDecoration(border:OutlineInputBorder(),labelText:'Hub IP (optional fallback)')),
       const SizedBox(height:12),
       TextField(controller:queue,decoration:const InputDecoration(border:OutlineInputBorder(),labelText:'LPR queue name',helperText:'Windows DIGITUS utility → Device Properties')),
       const SizedBox(height:8),
       OutlinedButton.icon(onPressed:save,icon:const Icon(Icons.save),label:const Text('Save hub')),
       OutlinedButton.icon(onPressed:inspectQueue,icon:const Icon(Icons.fact_check_outlined),label:const Text('Inspect LPR queue')),
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
       if(pdfBytes!=null)SizedBox(height:320,child:PdfPreview(
         build:(_)=>pdfBytes!,allowPrinting:false,allowSharing:false,
         canChangePageFormat:false,canChangeOrientation:false)),
       const SizedBox(height:12),
       FilledButton.icon(onPressed:pdfBytes==null?null:printFile,icon:const Icon(Icons.print),label:const Text('Open Android print dialog')),
       const SizedBox(height:8),
       const Text('Direct LPR to Canon G2420 is disabled until a compatible Canon printer-language driver is implemented.'),
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
