import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Network-only RFC 1179 LPR/LPD transport for DIGITUS DA-70254.
/// Transmits ALREADY ENCODED printer-language bytes; no PDF conversion here.
class LprTransport {
  const LprTransport();
  static final _ascii = ascii;

  Future<String> queryQueue({
    required String host,
    required String queue,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _validate(host, queue);
    final socket = await Socket.connect(host, 515, timeout: timeout);
    try {
      socket.add(Uint8List.fromList([3, ..._ascii.encode('$queue\n')]));
      await socket.flush();
      final response = <int>[];
      final done = Completer<void>();
      late StreamSubscription<Uint8List> subscription;
      subscription = socket.listen((chunk) {
        response.addAll(chunk);
        if (response.length > 65536) {
          subscription.cancel();
          if (!done.isCompleted) done.complete();
        }
      }, onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      }, onDone: () {
        if (!done.isCompleted) done.complete();
      }, cancelOnError: true);
      await done.future.timeout(timeout, onTimeout: () {});
      await subscription.cancel();
      return utf8.decode(response, allowMalformed: true);
    } finally {
      socket.destroy();
    }
  }

  Future<void> sendPrinterReadyData({
    required String host,
    required String queue,
    required Uint8List printerLanguageData,
    String documentName = 'Android print job',
    Duration timeout = const Duration(seconds: 20),
  }) async {
    _validate(host, queue);
    if (printerLanguageData.isEmpty) {
      throw ArgumentError('Cannot send an empty printer-language stream.');
    }
    // Limits avoid integer/LPD header overflows and accidental very large jobs.
    if (printerLanguageData.length > 100 * 1024 * 1024) {
      throw ArgumentError('Print job exceeds the 100 MiB prototype limit.');
    }
    final id = (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 1000;
    final number = id.toString().padLeft(3, '0');
    final dataFile = 'dfA${number}android';
    final controlFile = 'cfA${number}android';
    final cleanName = documentName.replaceAll(RegExp(r'[\r\n\x00-\x1f]'), ' ').trim();
    final control = _ascii.encode(
      'Handroid\nPandroid\nJ${cleanName.isEmpty ? 'Document' : cleanName}\n'
      'l$dataFile\nU$dataFile\nNdocument\n',
    );
    final socket = await Socket.connect(host, 515, timeout: timeout);
    final iter = StreamIterator<Uint8List>(socket);
    // StreamIterator may buffer multiple ACKs; consume exactly one byte at a time.
    final ackBytes = <int>[];
    Future<void> checkAck(String stage) async {
      while (ackBytes.isEmpty) {
        if (!await iter.moveNext().timeout(timeout)) {
          throw SocketException('LPD closed connection during $stage');
        }
        ackBytes.addAll(iter.current);
      }
      final response = ackBytes.removeAt(0);
      if (response != 0) {
        throw SocketException('LPD rejected $stage (code $response)');
      }
    }
    Future<void> line(int code, String command) async {
      socket.add([code, ..._ascii.encode('$command\n')]);
      await socket.flush();
    }
    try {
      await line(2, queue);
      await checkAck('queue selection');
      await line(2, '${control.length} $controlFile');
      await checkAck('control-file header');
      socket.add([...control, 0]);
      await socket.flush();
      await checkAck('control-file upload');
      await line(3, '${printerLanguageData.length} $dataFile');
      await checkAck('data-file header');
      socket.add(printerLanguageData);
      socket.add([0]);
      await socket.flush();
      await checkAck('data-file upload');
    } finally {
      await iter.cancel();
      socket.destroy();
    }
  }

  void _validate(String host, String queue) {
    if (host.trim().isEmpty || host.contains(RegExp(r'[\s\r\n]'))) {
      throw ArgumentError('Invalid print server address');
    }
    if (!RegExp(r'^[a-zA-Z0-9_.-]{1,80}$').hasMatch(queue)) {
      throw ArgumentError('Invalid LPR queue name');
    }
  }
}
