import 'package:fleetpilot/garage/trial_cancellation_control.dart';
import 'package:fleetpilot/garage/trial_cancellation_repository.dart';
import 'package:flutter/material.dart';
import 'package:fleetpilot/garage/billing_screen.dart';
import 'package:fleetpilot/garage/entitlement_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const workspace = '00000000-0000-4000-8000-000000000002';
  const actor = '00000000-0000-4000-8000-000000000001';
  for (final scenario in ['owner trial', 'member trial', 'owner paid', 'expired trial', 'unavailable']) {
    testWidgets('billing cancellation visibility: $scenario', (tester) async {
      var calls = 0;
      final repository = GarageTrialCancellationRepository(enabled:true,
        supabaseUrl:'https://fyestmquqvkdebxxbcky.supabase.co',
        currentUserId:() => actor, currentSessionKey:() => 'synthetic',
        invoke:(_) async { calls++; return null; });
      final read = scenario == 'unavailable'
        ? const GarageEntitlementRead.unavailable()
        : GarageEntitlementRead.verified(GarageEntitlement(active:true,
          source:scenario == 'owner paid' ? GarageEntitlementSource.paid : GarageEntitlementSource.trial,
          accessEndsAt:DateTime.now().toUtc().add(Duration(days:scenario == 'expired trial' ? -1 : 1))));
      await tester.pumpWidget(MaterialApp(home: GarageBillingScreen(
        workshopName:'Synthetic workshop', workspaceId:workspace,
        isOwner:scenario != 'member trial', cancellationRepository:repository,
        loadEntitlement:() async => read)));
      await tester.pumpAndSettle();
      expect(find.text('Cancel test trial'), scenario == 'owner trial' ? findsOneWidget : findsNothing);
      expect(calls, 0);
    });
  }
  for (final confirm in [false, true]) {
    testWidgets('explicit confirmation $confirm governs dispatch and refresh', (tester) async {
      var calls = 0; var refreshes = 0;
      final r = GarageTrialCancellationRepository(enabled:true,
        supabaseUrl:'https://fyestmquqvkdebxxbcky.supabase.co',
        currentUserId:() => actor, currentSessionKey:() => 'synthetic',
        invoke:(_) async { calls++; return {'status':'canceled',
          'canceled_at':'2026-10-26T21:00:00Z'}; });
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        GarageTrialCancellationControl(repository:r, workspaceId:workspace,
          trialEndsAt:DateTime.now().toUtc().add(const Duration(days:1)),
          onRefresh:() => refreshes++))));
      await tester.tap(find.text('Cancel test trial')); await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.textContaining('ends immediately'), findsOneWidget);
      await tester.tap(confirm ? find.widgetWithText(FilledButton, 'Cancel test trial') :
        find.text('Keep trial'));
      await tester.pumpAndSettle();
      expect(calls, confirm ? 1 : 0); expect(refreshes, confirm ? 1 : 0);
      if (confirm) {
        expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
      }
    });
  }
  testWidgets('account replacement during dialog prevents dispatch', (tester) async {
    var user = actor; var calls = 0;
    final r = GarageTrialCancellationRepository(enabled:true,
      supabaseUrl:'https://fyestmquqvkdebxxbcky.supabase.co',
      currentUserId:() => user, currentSessionKey:() => 'synthetic',
      invoke:(_) async { calls++; return null; });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      GarageTrialCancellationControl(repository:r, workspaceId:workspace,
        trialEndsAt:DateTime.now().toUtc().add(const Duration(days:1)), onRefresh:() {}))));
    await tester.tap(find.text('Cancel test trial')); await tester.pumpAndSettle();
    user = '00000000-0000-4000-8000-000000000003';
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel test trial'));
    await tester.pumpAndSettle(); expect(calls, 0);
  });
}
