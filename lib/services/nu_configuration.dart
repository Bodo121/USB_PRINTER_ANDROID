import 'dart:typed_data';

/// USB configuration descriptors returned by NU control transfers.
/// This parser is independent of TCP and does not claim a USB interface.
class NuEndpoint {
  const NuEndpoint(this.address,this.attributes,this.maxPacketSize);
  final int address,attributes,maxPacketSize;
  bool get isBulk => (attributes & 3)==2;
  bool get isIn => (address & 0x80)!=0;
  String get hexAddress => '0x${address.toRadixString(16).padLeft(2,'0')}';
}
class NuInterface {
  const NuInterface(this.number,this.alternateSetting,this.classCode,
    this.subclass,this.protocol,this.endpoints);
  final int number,alternateSetting,classCode,subclass,protocol;
  final List<NuEndpoint> endpoints;
  bool get isPrinter => classCode==7;
  NuEndpoint? get bulkOut {
    for(final endpoint in endpoints){
      if(endpoint.isBulk && !endpoint.isIn)return endpoint;
    }
    return null;
  }
  NuEndpoint? get bulkIn {
    for(final endpoint in endpoints){
      if(endpoint.isBulk && endpoint.isIn)return endpoint;
    }
    return null;
  }
}
class NuConfiguration {
  const NuConfiguration(this.totalLength,this.interfaces);
  final int totalLength;
  final List<NuInterface> interfaces;
  NuInterface? get printerInterface {
    for(final interface in interfaces){
      if(interface.isPrinter && interface.bulkOut!=null)return interface;
    }
    return null;
  }
}
class NuConfigurationDecoder {
  static NuConfiguration decode(Uint8List b) {
    if(b.length<9 || b[0]!=9 || b[1]!=2){
      throw const FormatException('No USB configuration descriptor header');
    }
    final length=b[2]|(b[3]<<8);
    if(length!=b.length || length>4096){
      throw const FormatException('USB configuration truncated or invalid');
    }
    final configurations=<NuInterface>[];
    var pos=9;
    int? number,alternate,klass,subclass,protocol,expectedCount;
    final endpoints=<NuEndpoint>[];
    void finish(){
      if(number==null)return;
      if(endpoints.length!=expectedCount){
        throw const FormatException('USB endpoint descriptor count mismatch');
      }
      configurations.add(NuInterface(number,alternate!,klass!,subclass!,
        protocol!,List.unmodifiable(endpoints)));
      endpoints.clear();
    }
    while(pos<length){
      if(pos+2>length || b[pos]<2 || pos+b[pos]>length){
        throw const FormatException('Malformed USB descriptor boundary');
      }
      final size=b[pos],kind=b[pos+1];
      if(kind==4){
        if(size<9)throw const FormatException('Invalid interface descriptor');
        finish();
        number=b[pos+2];alternate=b[pos+3];expectedCount=b[pos+4];
        klass=b[pos+5];subclass=b[pos+6];protocol=b[pos+7];
      } else if(kind==5){
        if(size<7 || number==null){
          throw const FormatException('Invalid endpoint descriptor');
        }
        endpoints.add(NuEndpoint(b[pos+2],b[pos+3],
          b[pos+4]|(b[pos+5]<<8)));
      }
      pos+=size;
    }
    finish();
    if(configurations.isEmpty){
      throw const FormatException('No USB interface descriptors');
    }
    return NuConfiguration(length,List.unmodifiable(configurations));
  }
}
