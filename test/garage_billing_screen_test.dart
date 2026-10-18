import 'dart:async';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:fleetpilot/ecosystem/ecosystem_module_hub.dart';
import 'package:fleetpilot/garage/billing_screen.dart';
import 'package:fleetpilot/garage/entitlement_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late MockClient transport;
  var requests = 0;
  setUpAll(() async {
    transport = MockClient((request) async {
      requests++;
      return http.Response('[]', 200, request: request,
        headers: {'content-type': 'application/json'});
    });
    client = SupabaseClient('https://billing.example.test', 'test-key',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    // Initialize the SDK JSON worker outside the widget test's fake clock.
    await client.from('fixture_warmup').select();
  });
  tearDownAll(() async { await client.dispose(); transport.close(); });
  tearDown(() => AppLocale.language.value = 'en');
  for (final language in supportedLanguages) {
    testWidgets('$language billing notice fits a narrow phone without payment controls', (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppLocale.language.value = language;
      await tester.pumpWidget(const MaterialApp(home: GarageBillingScreen(
        workshopName: 'Workshop with a long name', isOwner: true)));
      await tester.pumpAndSettle();
      expect(find.text(GarageBillingScreen.text(2)), findsOneWidget);
      expect(find.text(GarageBillingScreen.text(4)), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('non-owner direct screen does not expose workshop billing content', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GarageBillingScreen(
      workshopName: 'Private workshop', isOwner: false)));
    expect(find.text(GarageBillingScreen.text(1)), findsOneWidget);
    expect(find.text('Private workshop'), findsNothing);
    expect(find.text(GarageBillingScreen.text(4)), findsNothing);
  });
  testWidgets('visible page follows locale changes', (tester) async {
    AppLocale.language.value = 'en';
    await tester.pumpWidget(const MaterialApp(home: GarageBillingScreen(
      workshopName: 'Workshop', isOwner: true)));
    AppLocale.language.value = 'pl'; await tester.pump();
    expect(find.text('Subskrypcja i płatności'), findsOneWidget);
    expect(find.text('Subscription and payments'), findsNothing);
  });
  testWidgets('verified trial is labeled from the server decision', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GarageBillingScreen(
      workshopName: 'Workshop', isOwner: true,
      loadEntitlement: () async => GarageEntitlementRead.verified(
        GarageEntitlement(active: true,
          source: GarageEntitlementSource.trial,
          accessEndsAt: DateTime.utc(2026, 10, 25, 8))),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Sandbox access'), findsOneWidget);
    expect(find.text('Trial access confirmed until 2026-10-25 08:00 UTC'),
      findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    // Dispose the page so its future expiry timer cannot outlive the test.
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('expired authoritative access is not displayed as confirmed',
      (tester) async {
    AppLocale.language.value = 'en';
    await tester.pumpWidget(MaterialApp(home: GarageBillingScreen(
      workshopName: 'Workshop', isOwner: true,
      loadEntitlement: () async => GarageEntitlementRead.verified(
        GarageEntitlement(active: true,
          source: GarageEntitlementSource.paid,
          accessEndsAt: DateTime.utc(2020, 1, 1))),
    )));
    await tester.pumpAndSettle();
    expect(find.text('No current trial or paid access'), findsOneWidget);
    expect(find.textContaining('confirmed until'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open billing page automatically stops showing an expired trial',
      (tester) async {
    AppLocale.language.value = 'en';
    var instant = DateTime.utc(2030, 1, 1, 12);
    final expires = instant.add(const Duration(seconds: 2));
    var loads = 0;
    await tester.pumpWidget(MaterialApp(home: GarageBillingScreen(
      workshopName: 'Workshop', workspaceId: 'workspace-A',
      isOwner: true, now: () => instant,
      loadEntitlement: () async {
        loads++;
        return GarageEntitlementRead.verified(GarageEntitlement(
          active: true, source: GarageEntitlementSource.trial,
          accessEndsAt: expires));
      })));
    await tester.pumpAndSettle();
    expect(find.textContaining('Trial access confirmed until'), findsOneWidget);
    expect(loads, 1);

    instant = expires;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('No current trial or paid access'), findsOneWidget);
    expect(find.textContaining('confirmed until'), findsNothing);
    expect(loads, 1, reason: 'The expiry refresh must not issue new requests');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leaving billing screen cancels an upcoming expiry refresh',
      (tester) async {
    AppLocale.language.value = 'en';
    var instant = DateTime.utc(2030, 1, 1, 12);
    final expires = instant.add(const Duration(seconds: 2));
    await tester.pumpWidget(MaterialApp(home: GarageBillingScreen(
      workshopName: 'Workshop', workspaceId: 'workspace-A',
      isOwner: true, now: () => instant,
      loadEntitlement: () async => GarageEntitlementRead.verified(
        GarageEntitlement(active: true,
          source: GarageEntitlementSource.paid, accessEndsAt: expires)))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Paid access confirmed until'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    instant = expires;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable read never appears active', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GarageBillingScreen(
      workshopName: 'Workshop', isOwner: true,
      loadEntitlement: () async => const GarageEntitlementRead.unavailable(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Access could not be verified'), findsOneWidget);
    expect(find.textContaining('confirmed until'), findsNothing);
  });
  testWidgets('switching workshops discards stale entitlement before reload',
      (tester) async {
    AppLocale.language.value = 'en';
    final first = Completer<GarageEntitlementRead>();
    final second = Completer<GarageEntitlementRead>();
    var firstCalls = 0;
    var secondCalls = 0;
    Widget page(String workspaceId, GarageEntitlementLoader loader) =>
        MaterialApp(home: GarageBillingScreen(
          workshopName: 'Same workshop name', workspaceId: workspaceId,
          isOwner: true, loadEntitlement: loader));

    await tester.pumpWidget(page('workspace-A', () {
      firstCalls++;
      return first.future;
    }));
    first.complete(GarageEntitlementRead.verified(GarageEntitlement(
      active: true, source: GarageEntitlementSource.trial,
      accessEndsAt: DateTime.utc(2026, 10, 25, 8))));
    await tester.pumpAndSettle();
    expect(find.text('Trial access confirmed until 2026-10-25 08:00 UTC'),
      findsOneWidget);
    expect(firstCalls, 1);

    await tester.pumpWidget(page('workspace-B', () {
      secondCalls++;
      return second.future;
    }));
    await tester.pump();
    expect(secondCalls, 1);
    expect(find.textContaining('confirmed until'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    second.complete(const GarageEntitlementRead.unavailable());
    await tester.pumpAndSettle();
    expect(find.text('Access could not be verified'), findsOneWidget);
    expect(find.textContaining('confirmed until'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late old-workshop response never restores access',
      (tester) async {
    AppLocale.language.value = 'en';
    final oldWorkspace = Completer<GarageEntitlementRead>();
    final newWorkspace = Completer<GarageEntitlementRead>();
    Widget screen(String id, GarageEntitlementLoader loader) =>
        MaterialApp(home: GarageBillingScreen(
          workshopName: 'Same public name', workspaceId: id, isOwner: true,
          loadEntitlement: loader));

    await tester.pumpWidget(screen('workspace-A', () => oldWorkspace.future));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(screen('workspace-B', () => newWorkspace.future));
    newWorkspace.complete(const GarageEntitlementRead.unavailable());
    await tester.pumpAndSettle();
    expect(find.text('Access could not be verified'), findsOneWidget);
    expect(find.textContaining('confirmed until'), findsNothing);

    // A slow positive reply for the old workshop must be ignored by the
    // FutureBuilder already bound to workspace B.
    oldWorkspace.complete(GarageEntitlementRead.verified(GarageEntitlement(
      active: true, source: GarageEntitlementSource.paid,
      accessEndsAt: DateTime.utc(2026, 11, 1))));
    await tester.pumpAndSettle();
    expect(find.text('Access could not be verified'), findsOneWidget);
    expect(find.textContaining('confirmed until'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new owner loader invalidates old confirmed trial for same workshop',
      (tester) async {
    AppLocale.language.value = 'en';
    const workshopId = 'workspace-A';
    final pending = Completer<GarageEntitlementRead>();
    await tester.pumpWidget(MaterialApp(home: GarageBillingScreen(
      workshopName: 'Workshop', workspaceId: workshopId, isOwner: true,
      loadEntitlement: () async => GarageEntitlementRead.verified(
        GarageEntitlement(active: true, source: GarageEntitlementSource.trial,
          accessEndsAt: DateTime.utc(2026, 10, 25, 8))))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Trial access confirmed'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: GarageBillingScreen(
      workshopName: 'Workshop', workspaceId: workshopId, isOwner: true,
      loadEntitlement: () => pending.future)));
    await tester.pump();
    expect(find.textContaining('confirmed until'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(const GarageEntitlementRead.unavailable());
    await tester.pumpAndSettle();
    expect(find.text('Access could not be verified'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('losing ownership hides prior billing status without a new read',
      (tester) async {
    AppLocale.language.value = 'en';
    var calls = 0;
    GarageEntitlementLoader loader = () async {
      calls++;
      return GarageEntitlementRead.verified(GarageEntitlement(
        active: true, source: GarageEntitlementSource.paid,
        accessEndsAt: DateTime.utc(2026, 11, 1)));
    };
    await tester.pumpWidget(MaterialApp(home: GarageBillingScreen(
      workshopName: 'Workshop', workspaceId: 'workspace-A',
      isOwner: true, loadEntitlement: loader)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Paid access confirmed'), findsOneWidget);
    expect(calls, 1);

    await tester.pumpWidget(MaterialApp(home: GarageBillingScreen(
      workshopName: 'Workshop', workspaceId: 'workspace-A',
      isOwner: false, loadEntitlement: loader)));
    await tester.pumpAndSettle();
    expect(find.text(GarageBillingScreen.text(1)), findsOneWidget);
    expect(find.textContaining('confirmed until'), findsNothing);
    expect(find.text('Workshop'), findsNothing);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  test('access status has all supported translations', () {
    for (final language in supportedLanguages) {
      final status = GarageBillingScreen.statusTranslations[language];
      expect(status, isNotNull, reason: language);
      expect(status, hasLength(5), reason: language);
      expect(status![1], contains('{date}'), reason: language);
      expect(status[2], contains('{date}'), reason: language);
    }
  });
  for (final owner in [true, false]) {
    testWidgets('More exposes billing only to owner=$owner without API reads', (tester) async {
      AppLocale.language.value = 'en';
      final before = requests;
      await tester.pumpWidget(MaterialApp(home: EcosystemModuleHub(client: client,
        destination: EcosystemDestination(EcosystemModule.workshop,
          workspaceId: '11111111-1111-4111-8111-111111111111',
          name: 'Workshop', canConfigure: owner))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('garage_tab_4')));
      await tester.pumpAndSettle();
      expect(find.text(GarageBillingScreen.text(0)), owner ? findsOneWidget : findsNothing);
      if (owner) {
        await tester.tap(find.text(GarageBillingScreen.text(0)));
        await tester.pumpAndSettle();
        expect(find.text(GarageBillingScreen.text(2)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      expect(requests, before);
    });
  }
}
