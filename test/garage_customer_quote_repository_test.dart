import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/garage/customer_quote_repository.dart';

Map<String, Object?> rawQuote({
  int revision = 1,
  bool approved = false,
  int unitMinor = 3000,
  int taxMinor = 1200,
  String currency = 'GBP',
}) => {
      'revision': revision,
      'currency': currency,
      'subtotal_minor': 2 * unitMinor,
      'tax_minor': taxMinor,
      'total_minor': 2 * unitMinor + taxMinor,
      'approved': approved,
      'lines': [
        {
          'type': 'labour',
          'description': 'Brake inspection and repair',
          'quantity': 2,
          'unit_price_minor': unitMinor,
          'tax_minor': taxMinor,
        },
      ],
    };

void main() {
  test('parses a verified private customer quote and remains immutable', () {
    final quote = GarageCustomerQuoteRepository.parse(rawQuote())!;
    expect(quote.revision, 1);
    expect(quote.currency, 'GBP');
    expect(quote.subtotalMinor, 6000);
    expect(quote.taxMinor, 1200);
    expect(quote.totalMinor, 7200);
    expect(quote.formatMinor(quote.totalMinor), '£72.00');
    expect(quote.lines.single.totalMinor, 7200);
    expect(() => quote.lines.clear(), throwsUnsupportedError);
  });

  test('uses correct pence, cents and grosz formatting', () {
    for (final variant in [
      ('GBP', '£72.00'),
      ('EUR', '€72.00'),
      ('PLN', '72,00 zł'),
    ]) {
      final quote = GarageCustomerQuoteRepository.parse(
        rawQuote(currency: variant.$1),
      )!;
      expect(quote.formatMinor(quote.totalMinor), variant.$2);
    }
  });

  test('supports zero-, two- and three-decimal currency minor units', () {
    final cases = [
      ('JPY', 'JPY 7200'),
      ('KRW', 'KRW 7200'),
      ('KWD', 'KWD 7.200'),
      ('BHD', 'BHD 7.200'),
      ('CZK', 'CZK 72.00'),
      ('USD', 'USD 72.00'),
      ('CHF', 'CHF 72.00'),
    ];
    for (final c in cases) {
      final quote = GarageCustomerQuoteRepository.parse(
        rawQuote(currency: c.$1),
      )!;
      expect(quote.formatMinor(quote.totalMinor), c.$2);
    }
  });

  test('null quote means no published quote, not an approval', () {
    expect(GarageCustomerQuoteRepository.parse(null), isNull);
  });

  test('invalid response and unsupported currency fail closed', () {
    for (final payload in [
      <String, Object?>{},
      {'revision': 1},
      rawQuote(currency: 'XXX'),
      rawQuote(currency: 'gbp'),
      'malformed',
      [rawQuote()],
      14,
    ]) {
      expect(
        () => GarageCustomerQuoteRepository.parse(payload),
        throwsFormatException,
      );
    }
  });

  test('rejects altered totals, including mismatch across quote lines', () {
    for (final alteration in [
      <String, Object?>{'subtotal_minor': 7000},
      <String, Object?>{'tax_minor': 800},
      <String, Object?>{'total_minor': 9999},
      <String, Object?>{'total_minor': -1},
      <String, Object?>{'approved': 'true'},
      <String, Object?>{'revision': 0},
    ]) {
      expect(
        () => GarageCustomerQuoteRepository.parse({
          ...rawQuote(),
          ...alteration,
        }),
        throwsFormatException,
      );
    }
  });

  test('rejects malformed or missing line fields', () {
    for (final line in [
      {'type': 'part'},
      {'type': 'custom', 'description': 'Tax',
       'quantity': 2, 'unit_price_minor': 3000, 'tax_minor': 1200},
      {'type': 'part', 'description': 'Part',
       'quantity': 0, 'unit_price_minor': 3000, 'tax_minor': 1200},
      {'type': 'labour', 'description': 'Labor',
       'quantity': 2.2, 'unit_price_minor': 3000, 'tax_minor': 1200},
      {'type': 'labour', 'description': 'Labor',
       'quantity': 2, 'unit_price_minor': -1, 'tax_minor': 1200},
      {'type': 'part', 'description': 'Part',
       'quantity': 1001, 'unit_price_minor': 3000, 'tax_minor': 1200},
    ]) {
      expect(
        () => GarageCustomerQuoteRepository.parse({
          ...rawQuote(),
          'lines': [line],
        }),
        throwsFormatException,
      );
    }
    for (final lines in [[], 'not an array']) {
      expect(
        () => GarageCustomerQuoteRepository.parse({
          ...rawQuote(),
          'lines': lines,
        }),
        throwsFormatException,
      );
    }
  });
}
