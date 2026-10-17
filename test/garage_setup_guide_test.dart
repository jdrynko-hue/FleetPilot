import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:fleetpilot/ecosystem/ecosystem_module_hub.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/setup_guide.dart';

void main() {
  late SupabaseClient client;
  late MockClient transport;
  setUpAll(() async {
    transport = MockClient((request) async => http.Response('[]', 200, request: request,
      headers: {'content-type': 'application/json'}));
    client = SupabaseClient('https://setup.example.test', 'mock-only', httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    // Start the SDK JSON worker outside the widget test's fake clock.
    await client.from('fixture_warmup').select();
  });
  tearDownAll(() async { await client.dispose(); transport.close(); });
  for (final owner in [false, true]) {
    testWidgets('setup navigation follows workshop configuration permission ($owner)', (tester) async {
      await tester.pumpWidget(MaterialApp(home: EcosystemModuleHub(client: client,
        destination: EcosystemDestination(EcosystemModule.workshop,
          workspaceId: '00000000-0000-4000-8000-000000000001', name: 'QA workshop',
          canConfigure: owner))));
      await tester.pumpAndSettle();
      expect(find.byType(GarageSetupGuide), owner ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  test('setup copy covers every supported language', () {
    expect(GarageSetupGuide.copy.keys.toSet(), supportedLanguages.toSet());
    for (final copy in GarageSetupGuide.copy.values) {
      expect(copy.length, 2);
      expect(copy.every((value) => value.trim().isNotEmpty), isTrue);
    }
  });
  for (final language in supportedLanguages) {
    testWidgets('setup guide fits 320px and opens each step in $language', (tester) async {
      AppLocale.language.value = language;
      addTearDown(() => AppLocale.language.value = 'en');
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [
        GarageSetupGuide(openProfile: () => opened.add('profile'),
          openCalendar: () => opened.add('calendar'), openRequests: () => opened.add('requests')),
      ]))));
      await tester.pumpAndSettle();
      expect(find.text(GarageSetupGuide.copy[language]![0]), findsOneWidget);
      expect(opened, isEmpty);
      for (final key in ['bookingProfile', 'calendarSettings', 'customerRequests']) {
        final step = find.byKey(Key('garage_setup_$key'));
        await tester.ensureVisible(step);
        await tester.tap(step);
        await tester.pumpAndSettle();
      }
      expect(opened, ['profile', 'calendar', 'requests']);
      expect(tester.takeException(), isNull);
    });
  }
}
