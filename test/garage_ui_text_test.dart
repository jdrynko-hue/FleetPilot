import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:fleetpilot/ecosystem/ecosystem_gate.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'package:fleetpilot/garage/quote_currency_picker.dart';
import 'package:fleetpilot/garage/quote_order_repository.dart';
import 'package:fleetpilot/garage/workshop_quotes_screen.dart';
import 'package:fleetpilot/garage/repair_requests_screen.dart';
import 'package:fleetpilot/garage/repair_bridge_repository.dart';
import 'garage_repair_bridge_repository_test.dart' as fixture;

void main() {
  tearDown(() => AppLocale.language.value = 'en');

  test('published quote and approval text interpolates values across 12 locales', () {
    for (final language in supportedLanguages) {
      final totals = GarageUiText.format('quoteConfirmTotals',
        {'count': 2, 'total': 'GBP 45.00'}, language: language);
      expect(totals, contains('2'), reason: language);
      expect(totals, contains('GBP 45.00'), reason: language);
      expect(totals, isNot(contains('{count}')), reason: language);
      expect(totals, isNot(contains('{total}')), reason: language);
      final status = GarageUiText.format('quotePublishedStatus',
        {'revision': 3}, language: language);
      expect(status, contains('3'), reason: language);
      expect(status, isNot(contains('{revision}')), reason: language);
      final locked = GarageUiText.format('quoteCurrencyLocked',
        {'currency': 'EUR'}, language: language);
      expect(locked, contains('EUR'), reason: language);
      for (final key in [
        'quoteLoadError', 'quoteIntro', 'quoteNoOrders',
        'quoteCurrencyBlocked', 'quoteInvalidLines',
        'quoteUncertain', 'quoteBackToOrders',
      ]) {
        expect(GarageUiText.get(key, language: language), isNotEmpty,
          reason: '$language $key');
      }
    }
  });

  test('quote editor labels and currency placeholders are present in every language', () {
    for (final locale in supportedLanguages) {
      for (final key in [
        'estimateCurrency', 'estimateCurrencyHint', 'workshopEstimates',
        'newEstimate', 'addQuoteItem', 'publishEstimate', 'itemNumber',
        'quoteType', 'quoteLabour', 'quotePart', 'quoteOther',
        'quoteDescription', 'quoteQuantity', 'quoteUnitPrice',
        'quoteLineTax', 'quotePublishing', 'quotePublishQuestion',
        'quoteBack', 'quotePublish',
      ]) {
        final translated = GarageUiText.get(key, language: locale);
        expect(translated.trim(), isNotEmpty, reason: '$locale $key');
        expect(translated, isNot(key), reason: '$locale $key');
      }
      expect(GarageUiText.format('quoteUnitPrice', {'currency': 'GBP'},
        language: locale), contains('GBP'));
      expect(GarageUiText.format('quoteLineTax', {'currency': 'PLN'},
        language: locale), contains('PLN'));
      expect(GarageUiText.format('itemNumber', {'number': 3},
        language: locale), contains('3'));
    }
  });

  testWidgets('Ukrainian quote currency selector fits 360px', (tester) async {
    AppLocale.language.value = 'uk';
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16),
        child: GarageQuoteCurrencyPicker(
          currency: 'GBP', onChanged: (_) {},
        )),
    )));
    expect(find.text('Валюта кошторису'), findsOneWidget);
    expect(find.text('Суми зберігаються у вибраній валюті.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Czech quote editor has localized primary fields and actions',
      (tester) async {
    AppLocale.language.value = 'cs';
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: GarageQuoteEditorScreen(
      order: const GarageQuoteOrder(
        id: '00000000-0000-4000-8000-000000000001',
        complaint: 'Brakes', status: 'diagnosing',
      ),
      loadCurrency: () async =>
        const GarageQuoteCurrencySelection('GBP', locked: false),
      publish: (_, __) async => 1,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Nová cenová nabídka'), findsOneWidget);
    expect(find.text('Položka 1'), findsOneWidget);
    expect(find.text('Jednotková cena (GBP)'), findsOneWidget);
    expect(find.text('Zveřejnit cenovou nabídku'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  test('Garage module and timeline keys are covered in all 12 languages', () {
    expect(GarageUiText.labels.keys.toSet(), supportedLanguages.toSet());
    expect(GarageUiText.keys.toSet().length, GarageUiText.keys.length);
    for (final locale in supportedLanguages) {
      final items = GarageUiText.labels[locale]!;
      expect(items, hasLength(GarageUiText.keys.length), reason: locale);
      for (var i = 0; i < GarageUiText.keys.length; i++) {
        expect(items[i].trim(), isNotEmpty, reason: '$locale index $i');
        expect(items[i].trim(), isNot(GarageUiText.keys[i]),
            reason: '$locale missing translation at $i');
        expect(GarageUiText.get(GarageUiText.keys[i], language: locale),
            items[i], reason: '$locale at $i');
      }
    }
    expect(GarageUiText.get('repairTimeline', language: 'de'),
        'Reparaturverlauf');
    expect(GarageUiText.get('assignedMechanic', language: 'uk'),
        'Призначений механік');
    expect(GarageUiText.get('findWorkshop', language: 'invalid'),
        'Find a workshop');
    expect(GarageUiText.get('unknownKey'), 'unknownKey');
  });

  test('module picker labels are translated for supported non-English locales', () {
    // The module hub reads these labels directly from GarageUiText.
    // Keep this localization check independent of Supabase auth timers;
    // widget navigation and permissions are exercised in separate tests.
    for (final language in ['de', 'es', 'ro']) {
      final keys = ['fleetConnections', 'ordersEstimates',
        'fleetRequests', 'calendarBays'];
      for (final key in keys) {
        final translated = GarageUiText.get(key, language: language);
        expect(translated.trim(), isNotEmpty, reason: '$language: $key');
        expect(translated, isNot(GarageUiText.get(key, language: 'en')),
            reason: '$language: $key');
      }
    }
  });

  testWidgets('Ukrainian mobile module picker translates account and role entry',
      (tester) async {
    AppLocale.language.value = 'uk';
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: EcosystemGate(
      loadAccess: () async => const EcosystemAccess(hasFleet:false,garages:[]),
      signOut: () async => throw StateError('PRIVATE AUTH ERROR'),
      destinationBuilder: (_) => const Scaffold(body:Text('QA destination')),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Виберіть модуль'), findsOneWidget);
    expect(find.text('Створити автопарк'), findsOneWidget);
    expect(find.text('Записи до СТО'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ecosystem_logout')));
    await tester.pumpAndSettle();
    expect(find.textContaining('PRIVATE AUTH ERROR'), findsNothing);
    expect(find.text('Не вдалося вийти. Спробуйте ще раз.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('German repair detail renders assigned mechanic and event labels',
      (tester) async {
    AppLocale.language.value = 'de';
    final request = GarageRepairRequest(fixture.requestId, fixture.companyId,
        fixture.workshopId, 'Brakes', 'accepted');
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: request,
      load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status:'accepted', workOrderId:fixture.orderId, orderStatus:'ready',
        assigned:true,
        history:[
          fixture.event('request_sent','2026-10-14T09:00:00Z'),
          fixture.event('request_accepted','2026-10-14T09:01:00Z'),
          fixture.event('quote_approved','2026-10-14T09:02:00Z'),
          fixture.event('progress_updated','2026-10-14T09:03:00Z'),
        ],
      )),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Zugewiesener Mechaniker'), findsOneWidget);
    expect(find.text('Mechaniker zugewiesen'), findsOneWidget);
    expect(find.text('Abholbereit'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('repair_event_timeline')));
    await tester.tap(find.byKey(const Key('repair_event_timeline')));
    await tester.pumpAndSettle();
    expect(find.text('Anfrage gesendet'), findsOneWidget);
    expect(find.text('Von Werkstatt angenommen'), findsOneWidget);
    expect(find.text('Kostenvoranschlag genehmigt'), findsOneWidget);
    expect(find.textContaining('Version des Kostenvoranschlags: 1'),
        findsOneWidget);
  });
}
