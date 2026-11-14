import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A read-only snapshot of the DA-70254's built-in HTTP information pages.
///
/// The USB server can report a device "Ready" even if the Canon driver or
/// LPR queue is not compatible. Never equate web status with printed output.
class HubSnapshot {
  const HubSnapshot({
    required this.host,
    required this.serverName,
    required this.firmware,
    required this.deviceStatus,
    required this.reportedDevice,
    required this.isLikelyUsbHub,
    this.deviceIndex,
  });
  final String host;
  final String? serverName;
  final String? firmware;
  final String? deviceStatus;
  final String? reportedDevice;
  final int? deviceIndex;
  final bool isLikelyUsbHub;

  bool get usbOnline =>
      deviceStatus?.toLowerCase() == 'ready' ||
      deviceStatus?.toLowerCase() == 'online';

  /// True only for the server's web identity. Not print-job readiness.
  String get connectivityLabel =>
      isLikelyUsbHub ? 'USB sharing hub identified' : 'HTTP server detected';
}

class HubWebProbe {
  const HubWebProbe();

  static const paths = <String>[
    '/', '/status.htm', '/status.html', '/index.htm',
  ];

  /// Parses the web page as text rather than assuming a firmware-specific API.
  /// This also handles the older table markup used by firmware V.100.085.
  static HubSnapshot parse(String host, String html) {
    var stripped = html.replaceAll(
      RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>',
          caseSensitive: false), ' ');
    stripped = stripped
        .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</\s*(td|th|tr|p|div)\s*>',
            caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'[\t ]+'), ' ');

    String? afterLabel(String label) {
      final re = RegExp('(?:^|\\n)\\s*' + RegExp.escape(label) +
          r'\s*:?\s*(?:\n\s*)?([^\n]+)', caseSensitive: false);
      final match = re.firstMatch(stripped);
      return match?.group(1)?.trim();
    }

    final serverName = afterLabel('Server Name');
    final firmware = afterLabel('Firmware Version');
    final status = afterLabel('Device Status');
    final device = afterLabel('Device Name');
    final id = RegExp(r'Device\s+([1-4])\s+Information',
        caseSensitive: false).firstMatch(stripped);
    final identified = RegExp(
      r'(IP USB Sharing Station|Network USB Server|USB over IP Server)',
      caseSensitive: false,
    ).hasMatch(stripped);
    return HubSnapshot(
      host: host,
      serverName: serverName,
      firmware: firmware,
      reportedDevice: device,
      deviceStatus: status,
      deviceIndex: id == null ? null : int.tryParse(id.group(1)!),
      isLikelyUsbHub: identified,
    );
  }

  Future<HubSnapshot?> inspect(String host) async {
    final address = InternetAddress.tryParse(host);
    // No accidental requests to public websites or arbitrary hostnames.
    if (address == null || address.type != InternetAddressType.IPv4 ||
        !_isPrivate(address.rawAddress)) return null;

    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 650)
      ..idleTimeout = const Duration(milliseconds: 300)
      ..autoUncompress = true;
    try {
      for (final path in paths) {
        try {
          final req = await client
              .getUrl(Uri(scheme: 'http', host: host, path: path))
              .timeout(const Duration(milliseconds: 800));
          req.followRedirects = false;
          final response = await req.close().timeout(
              const Duration(milliseconds: 800));
          if (response.statusCode != HttpStatus.ok) {
            await response.drain<void>();
            continue;
          }
          final limited = <int>[];
          await for (final chunk in response.timeout(
              const Duration(milliseconds: 800))) {
            if (limited.length + chunk.length > 65536) break;
            limited.addAll(chunk);
          }
          final text = utf8.decode(limited, allowMalformed: true);
          final snapshot = parse(host, text);
          if (snapshot.isLikelyUsbHub) return snapshot;
        } catch (_) {
          // Older firmware uses varying paths. Try the next read-only page.
        }
      }
    } finally {
      client.close(force: true);
    }
    return null;
  }

  static bool _isPrivate(List<int> a) =>
      a[0] == 10 || a[0] == 192 && a[1] == 168 ||
      a[0] == 172 && a[1] >= 16 && a[1] <= 31;
}
