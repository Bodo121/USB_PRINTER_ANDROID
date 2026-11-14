import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/usb_port_diagnostics.dart';

void main() {
  test('parses multiple TCP ports and removes duplicates', () {
    expect(UsbPortDiagnostics.parsePorts('4660, 3240;515 4660'),
      [4660,3240,515]);
  });
  test('rejects invalid TCP ports', () {
    expect(()=>UsbPortDiagnostics.parsePorts('0, 65536'),throwsFormatException);
    expect(()=>UsbPortDiagnostics.parsePorts('abc'),throwsFormatException);
  });
  test('only private IPv4 destinations are scanned', () {
    expect(UsbPortDiagnostics.privateIpv4('192.168.0.74'),isTrue);
    expect(UsbPortDiagnostics.privateIpv4('8.8.8.8'),isFalse);
    expect(UsbPortDiagnostics.physicalPortCount,4);
    expect(UsbPortDiagnostics.serviceName(4660),contains('UNT'));
  });
}
