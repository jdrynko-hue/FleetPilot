import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/garage_currencies.dart';
import 'package:fleetpilot/garage/quote_currency_picker.dart';
import 'package:fleetpilot/garage/workshop_quote_publisher.dart';

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  test('defaults prioritize GBP, EUR and PLN followed by other codes', () {
    expect(GarageCurrencies.preferred, ['GBP', 'EUR', 'PLN']);
    expect(GarageCurrencies.others, containsAll(['USD', 'JPY', 'CHF', 'KWD']));
    expect(GarageCurrencies.others.toSet().intersection(
      GarageCurrencies.preferred.toSet(),
    ), isEmpty);
  });

  test('minor precision is correct and unknown codes fail closed', () {
    expect(GarageCurrencies.digits('JPY'), 0);
    expect(GarageCurrencies.digits('KWD'), 3);
    expect(GarageCurrencies.digits('GBP'), 2);
    expect(GarageCurrencies.formatMinor('JPY', 157), 'JPY 157');
    expect(GarageCurrencies.formatMinor('KWD', 157), 'KWD 0.157');
    expect(GarageCurrencies.formatMinor('PLN', 157), '1,57 zł');
    expect(GarageCurrencies.formatMinor('GBP', 157), '£1.57');
    expect(() => GarageCurrencies.digits('XXX'), throwsFormatException);
    expect(() => GarageCurrencies.formatMinor('USD', -1), throwsFormatException);
  });

  const line = GarageQuoteDraftLine(
    type: 'labour',
    description: 'Brake inspection',
    quantity: 2,
    unitPriceMinor: 3000,
    taxMinor: 1200,
  );

  test('publish payload uses chosen currency and integer minor units', () {
    for (final code in ['GBP', 'EUR', 'PLN', 'USD', 'JPY', 'KWD']) {
      final payload = GarageWorkshopQuotePublisher.payload(
        currency: code, lines: [line],
      );
      expect(payload['p_currency'], code);
      final items = payload['p_lines']! as List<Map<String, Object>>;
      expect(items.single['unit_price_minor'], 3000);
      expect(items.single['tax_minor'], 1200);
    }
  });

  test('publishing rejects invalid currency, empty and invalid line data', () {
    expect(
      () => GarageWorkshopQuotePublisher.payload(
        currency: 'NONE', lines: [line],
      ),
      throwsFormatException,
    );
    expect(
      () => GarageWorkshopQuotePublisher.payload(
        currency: 'USD', lines: [],
      ),
      throwsArgumentError,
    );
    expect(
      () => GarageWorkshopQuotePublisher.payload(
        currency: 'USD',
        lines: [
          const GarageQuoteDraftLine(
            type: 'part', description: 'Invalid',
            quantity: 1, unitPriceMinor: -500, taxMinor: 0,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  Future<void> renderPicker(
    WidgetTester tester, {
    required double width,
    required String currency,
    required ValueChanged<String> onChanged,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: GarageQuoteCurrencyPicker(
              currency: currency,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 375.0, 390.0, 900.0]) {
    testWidgets('currency selection does not overflow width $width',
        (tester) async {
      await renderPicker(
        tester,
        width: width,
        currency: 'GBP',
        onChanged: (_) {},
      );
      expect(find.text('Estimate currency'), findsOneWidget);
      expect(find.text('GBP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selects JPY as an alternative currency', (tester) async {
    String? selected;
    await renderPicker(
      tester, width: 390, currency: 'GBP',
      onChanged: (code) => selected = code,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('JPY').last);
    await tester.tap(find.text('JPY').last);
    await tester.pumpAndSettle();
    expect(selected, 'JPY');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Polish labels identify currency beside amount', (tester) async {
    AppLocale.language.value = 'pl';
    await renderPicker(
      tester, width: 375, currency: 'PLN', onChanged: (_) {},
    );
    expect(find.text('Waluta kosztorysu'), findsOneWidget);
    expect(find.textContaining('Kwota będzie'), findsOneWidget);
  });
}
