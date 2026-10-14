import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/pdf_saver.dart';
import 'package:fleetpilot/garage/media_repository.dart';

void main() {
  const pdfName = '00000000-0000-4000-8000-000000000998.pdf';

  test('canonical PDF name is stripped only before save', () {
    expect(GaragePdfSaver.baseName(pdfName),
      '00000000-0000-4000-8000-000000000998');
    for (final bad in [
      'invoice.pdf', '../invoice.pdf', 'customer@example.com.pdf',
      'ABCDEF00-0000-4000-8000-000000000998.pdf', 'a/b.pdf',
      '00000000-0000-4000-8000-000000000998.png',
      '00000000-0000-4000-8000-000000000998.pdf.pdf',
    ]) {
      expect(() => GaragePdfSaver.baseName(bad), throwsArgumentError);
    }
  });

  test('valid PDF header is accepted without network or platform APIs', () {
    final bytes = Uint8List.fromList('%PDF-1.7\nmock'.codeUnits);
    GaragePdfSaver.validateBytes(bytes);
  });

  test('empty, corrupted, non-PDF and oversized files are rejected', () {
    final bad = <Uint8List>[
      Uint8List(0),
      Uint8List.fromList([37,80,68,70]),
      Uint8List.fromList('not a PDF'.codeUnits),
      Uint8List.fromList('<svg/>'.codeUnits),
      Uint8List.fromList('%PDf-no'.codeUnits),
      Uint8List(GarageMediaPaths.maxFileBytes + 1),
    ];
    for (final bytes in bad) {
      expect(() => GaragePdfSaver.validateBytes(bytes), throwsFormatException);
    }
  });

  test('only exact 5 MiB is allowed as the largest PDF', () {
    final bytes = Uint8List(GarageMediaPaths.maxFileBytes);
    bytes.setRange(0, 5, '%PDF-'.codeUnits);
    GaragePdfSaver.validateBytes(bytes);
  });
}
