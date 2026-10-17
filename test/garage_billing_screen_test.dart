import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:fleetpilot/ecosystem/ecosystem_module_hub.dart';
import 'package:fleetpilot/garage/billing_screen.dart';
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
