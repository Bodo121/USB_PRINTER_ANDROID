import 'dart:typed_data';

/// Evidence-based, offline print-path compatibility gate.
/// It does not connect to the USB hub, generate commands, or print.
/// No captured USB payload is bundled or replayed.
class NuPrintAudit {
  static const int windowsSetupLength = 383;
  static const String windowsSetupStart = '57 54 b9 ed 21 b2 10 0f';
  static const String windowsSecondSetupStart = 'f1 f2 42 37 e3 19 00 d0';

  static bool beginsWithIvecXml(Uint8List raster) =>
      raster.length >= 5 &&
      raster[0] == 0x3c && raster[1] == 0x3f &&
      raster[2] == 0x78 && raster[3] == 0x6d &&
      raster[4] == 0x6c;

  static String firstBytes(Uint8List bytes, {int limit = 8}) =>
      bytes.take(limit).map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');

  /// The transport header alone cannot turn IVEC document bytes into
  /// the unknown 383-byte Windows USB setup transaction. Until the latter
  /// is understood and rebuilt from fields, fail closed before sending
  /// even a partial job. Never use a previous capture as live payload.
  static String diagnose(Uint8List raster) {
    if (raster.isEmpty) {
      throw const FormatException('No Canon raster bytes to analyze');
    }
    final xml = beginsWithIvecXml(raster);
    return [
      'MODE=OFFLINE_ONLY; TRANSMITTED_BYTES=0; NO_RETRY',
      'Generated IVEC job length=' + raster.length.toString(),
      'Generated prefix8=' + firstBytes(raster) +
          (xml ? ' (IVEC XML declaration)' : ' (format unverified)'),
      'Successful Windows trace seq41: binary USB OUT length=383;'
          ' prefix8=' + windowsSetupStart,
      'Windows seq76 second 383-byte setup: prefix8=' +
          windowsSecondSetupStart,
      'Windows seq44 returned 487 bytes after setup, whereas Android'
          ' using direct IVEC raster returned zero bytes.',
      'Mismatch: the generated document stream cannot be substituted'
          ' for this unidentified USB setup exchange.',
      'No physical printing attempted. Protocol setup/response processing'
          ' and Canon G2010 raster compatibility require validation.'
    ].join('\n');
  }
}
