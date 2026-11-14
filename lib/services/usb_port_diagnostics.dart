import 'dart:async';
import 'dart:io';

/// Read-only diagnostics for the four physical USB sockets and candidate
/// *network TCP service ports*. These are not interchangeable quantities.
class NetworkServicePort {
  const NetworkServicePort(this.port, this.open, this.description);
  final int port;
  final bool open;
  final String description;
}
class UsbPortDiagnostics {
  const UsbPortDiagnostics();

  static const defaultPorts = <int>[4660,3240,515];
  static const int physicalPortCount = 4;

  static List<int> parsePorts(String input) {
    final values = <int>{};
    for (final part in input.split(RegExp(r'[,;\s]+'))) {
      if (part.isEmpty) continue;
      final port = int.tryParse(part);
      if (port == null || port < 1 || port > 65535) {
        throw const FormatException('TCP ports must be integers between 1 and 65535');
      }
      values.add(port);
      if(values.length > 16) {
        throw const FormatException('Up to 16 TCP ports can be checked at once');
      }
    }
    if (values.isEmpty) throw const FormatException('Enter at least one TCP port');
    return values.toList(growable:false);
  }

  static String serviceName(int port) {
    if (port==4660) return 'NU V1.25 candidate (UNT\$ observed in capture)';
    if (port==3240) return 'Standard Linux USB/IP';
    if (port==515) return 'LPR printing';
    return 'Custom TCP service (protocol unknown)';
  }

  static bool privateIpv4(String host) {
    final parsed = InternetAddress.tryParse(host);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) return false;
    final address = parsed.rawAddress;
    return address[0] == 10 ||
      address[0] == 192 && address[1] == 168 ||
      address[0] == 172 && address[1] >= 16 && address[1] <= 31;
  }

  Future<List<NetworkServicePort>> check({
    required String host,
    required List<int> ports,
  }) async {
    if(!privateIpv4(host)) {
      throw const FormatException('Port checks are restricted to private LAN IPv4 addresses');
    }
    return Future.wait(ports.map((port) async {
      Socket? socket;
      try {
        socket = await Socket.connect(host, port,
          timeout:const Duration(milliseconds: 900));
        return NetworkServicePort(port,true,serviceName(port));
      } on SocketException {
        return NetworkServicePort(port,false,serviceName(port));
      } on TimeoutException {
        return NetworkServicePort(port,false,serviceName(port));
      } finally {
        socket?.destroy();
      }
    }));
  }
}
