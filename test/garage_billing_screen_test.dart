import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:fleetpilot/ecosystem/ecosystem_module_hub.dart';
import 'package:fleetpilot/garage/billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
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
      final client = SupabaseClient('https://example.supabase.co', 'test-key');
      addTearDown(client.dispose);
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
    });
  }
}
