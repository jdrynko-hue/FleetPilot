import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/auth/billing_markets.dart';
import 'package:fleetpilot/auth/create_company_screen.dart';
import 'package:fleetpilot/core/localization.dart';

void main() {
  setUp(() => AppLocale.language.value = 'en');

  test('supported fleet markets map to matching billing currencies', () {
    expect(currencyForFleetCountry('GB'), 'GBP');
    expect(currencyForFleetCountry(' pl '), 'PLN');
    expect(currencyForFleetCountry('DE'), 'EUR');
    expect(currencyForFleetCountry('FR'), 'EUR');
    expect(currencyForFleetCountry('US'), isNull);
    expect(currencyForFleetCountry(''), isNull);
    expect(supportedFleetCountries.keys.length, 23);
  });

  test('all supported countries have localized names and currencies', () {
    for (final country in supportedFleetCountries.keys) {
      expect(currencyForFleetCountry(country), isNotNull);
      expect(fleetCountryName(country), isNotEmpty);
      expect(fleetCountryName(country, locale: 'pl'), isNotEmpty);
    }
  });

  testWidgets('fleet registration requires a name and business attestation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CreateCompanyScreen(
        onCreated: () {},
        createCompany: ({required name, required country, required currency}) async {},
      ),
    ));

    final create = find.byType(FilledButton);
    expect(tester.widget<FilledButton>(create).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'QA Fleet');
    await tester.pump();
    expect(tester.widget<FilledButton>(create).onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
  });

  testWidgets('selected country drives the currency sent to fleet creation',
      (tester) async {
    final captured = <String, String>{};
    var created = 0;

    await tester.pumpWidget(MaterialApp(
      home: CreateCompanyScreen(
        onCreated: () => created++,
        createCompany: ({
          required String name,
          required String country,
          required String currency,
        }) async {
          // Assign through a captured map to avoid parameter shadowing.
          captured['name'] = name;
          captured['country'] = country;
          captured['currency'] = currency;
        },
      ),
    ));

    expect(find.text('GBP — British pound'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  QA Business  ');
    await tester.tap(find.byKey(const Key('fleet_country_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poland (PL)').last);
    await tester.pumpAndSettle();
    expect(find.text('PLN — Polish złoty'), findsOneWidget);

    final attestation = find.byType(CheckboxListTile);
    await tester.ensureVisible(attestation);
    await tester.pumpAndSettle();
    await tester.tap(attestation);
    await tester.pump();

    final createButton = find.byType(FilledButton);
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(createButton).onPressed, isNotNull);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(captured['name'], 'QA Business');
    expect(captured['country'], 'PL');
    expect(captured['currency'], 'PLN');
    expect(created, 1);
  });

  testWidgets('Polish mobile fleet registration shows country names',
      (tester) async {
    AppLocale.language.value = 'pl';
    addTearDown(() => AppLocale.language.value = 'en');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: CreateCompanyScreen(
        onCreated: () {},
        createCompany: ({required name, required country, required currency}) async {},
      ),
    ));
    expect(find.text('Wielka Brytania (GB)'), findsOneWidget);
    expect(find.text('GBP — funt brytyjski'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
