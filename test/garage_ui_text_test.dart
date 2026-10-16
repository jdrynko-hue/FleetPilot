import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:fleetpilot/ecosystem/ecosystem_gate.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'package:fleetpilot/garage/repair_requests_screen.dart';
import 'package:fleetpilot/garage/repair_bridge_repository.dart';
import 'garage_repair_bridge_repository_test.dart' as fixture;

void main() {
  tearDown(() => AppLocale.language.value = 'en');

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
