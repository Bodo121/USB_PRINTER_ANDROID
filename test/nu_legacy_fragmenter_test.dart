import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digitus_print/services/nu_legacy_fragmenter.dart';

void main() {
  test('Driver disassembly: legacy bulk OUT prepends 32 bytes', () {
    expect(NuLegacyFragmenter.legacyHeaderBytes, 0x20);
    expect(NuLegacyFragmenter.legacyAllocationLength(383), 415);
    expect(NuLegacyFragmenter.legacyAllocationLength(1024), 1056);
    expect(
      () => NuLegacyFragmenter.legacyAllocationLength(1025),
      throwsRangeError,
    );
    expect(
      () => NuLegacyFragmenter.legacyAllocationLength(0),
      throwsRangeError,
    );
  });

  test('Disassembled 0x400-byte clamp: 383-byte transaction untouched', () {
    final input = Uint8List.fromList(
      List<int>.generate(383, (i) => i & 255),
    );
    final fragments = NuLegacyFragmenter.splitOut(input).toList();
    expect(fragments.length, 1);
    expect(fragments.single.offset, 0);
    expect(fragments.single.count, 383);
    expect(fragments.single.last, isTrue);
    expect(fragments.single.bytes, orderedEquals(input));
  });

  test('2049 USB-client bytes require 1024, 1024, 1 fragments', () {
    final source = Uint8List.fromList(
      List<int>.generate(2049, (i) => (i * 13) & 255),
    );
    final chunks = NuLegacyFragmenter.splitOut(source).toList();
    expect(chunks.map((f) => f.count).toList(), <int>[1024, 1024, 1]);
    expect(chunks.map((f) => f.offset).toList(), <int>[0, 1024, 2048]);
    expect(chunks.last.last, isTrue);
    expect(
      chunks.expand((f) => f.bytes).toList(),
      orderedEquals(source),
    );
  });

  test('Partial USB buffer respects driver-side transfer offset', () {
    final source = Uint8List.fromList(List<int>.generate(2100, (i) => i & 255));
    final chunks = NuLegacyFragmenter.splitOut(
      source,
      initialOffset: 300,
    ).toList();
    expect(chunks.map((f) => f.count).toList(), <int>[1024, 776]);
    expect(chunks.map((f) => f.offset).toList(), <int>[300, 1324]);
    expect(chunks.last.last, isTrue);
  });

  test('No transfer data means no IO and no fragment', () {
    expect(NuLegacyFragmenter.splitOut(Uint8List(0)).toList(), isEmpty);
  });
}
