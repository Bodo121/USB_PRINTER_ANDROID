import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/hub_web_probe.dart';
import 'package:digitus_print/services/hub_discovery.dart';

void main() {
  test('Parses generic USB hub firmware status page', () {
    const html = '''
      <h2>Status</h2><table>
      <tr><td>Server Name</td><td>IP USB Sharing Station-0767DD</td></tr>
      <tr><td>Manufacturer</td><td>Generic</td></tr>
      <tr><td>Model</td><td>Network USB Server</td></tr>
      <tr><td>Firmware Version</td><td>V. 100.085</td></tr>
      </table>
      <h3>Device 1 Information</h3>
      <table><tr><td>Device Name</td><td>Canon G2010 series</td></tr>
      <tr><td>Link Status</td><td>Online</td></tr>
      <tr><td>Device Status</td><td>Ready</td></tr></table>
    ''';
    final snapshot = HubWebProbe.parse('192.168.0.74', html);
    expect(snapshot.isLikelyUsbHub, isTrue);
    expect(snapshot.serverName, 'IP USB Sharing Station-0767DD');
    expect(snapshot.firmware, 'V. 100.085');
    expect(snapshot.deviceStatus, 'Ready');
    expect(snapshot.deviceIndex, 1);
    // This is self-reported hardware text, never authoritative driver model.
    expect(snapshot.reportedDevice, 'Canon G2010 series');
  });

  test('Does not mistake unrelated HTTP server for DIGITUS hub', () {
    final result = HubWebProbe.parse('192.168.0.80', '<title>Router</title>');
    expect(result.isLikelyUsbHub, isFalse);
  });

  test('LPR queue errors do not count as evidence', () {
    expect(HubDiscovery.positiveEvidence('unknown queue lp'), isNull);
    expect(HubDiscovery.positiveEvidence('no such queue'), isNull);
    expect(HubDiscovery.positiveEvidence('no entries'), 'no entries');
  });
}
