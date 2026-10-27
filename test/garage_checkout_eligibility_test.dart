import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/billing_screen.dart';
import 'package:fleetpilot/garage/checkout_card.dart';
import 'package:fleetpilot/garage/checkout_repository.dart';
import 'package:fleetpilot/garage/entitlement_repository.dart';

void main() {
  const actor='00000000-0000-4000-8000-000000000001';
  const workspace='00000000-0000-4000-8000-000000000002';
  for (final scenario in ['fresh','legacy inactive','consumed','active trial','active paid','unavailable','loading']) {
    testWidgets('Checkout availability requires explicit server hint: $scenario',(tester) async {
      var calls=0;
      final repository=GarageCheckoutRepository(enabled:true,
        supabaseUrl:'https://fyestmquqvkdebxxbcky.supabase.co',
        currentUserId:()=>actor,currentSessionKey:()=> 'synthetic',
        invoke:(_)async {calls++;return null;});
      final active=scenario.startsWith('active');
      final status=GarageEntitlementRead.verified(GarageEntitlement(active:active,
        source:active ? (scenario=='active paid' ? GarageEntitlementSource.paid : GarageEntitlementSource.trial) : null,
        accessEndsAt:active ? DateTime.now().toUtc().add(const Duration(days:1)) : null),
        trialAvailable:scenario=='fresh');
      final pending=Completer<GarageEntitlementRead>();
      await tester.pumpWidget(MaterialApp(home:GarageBillingScreen(
        workshopName:'Synthetic',workspaceId:workspace,isOwner:true,checkoutRepository:repository,
        loadEntitlement:()=>scenario=='loading' ? pending.future : Future.value(
          scenario=='unavailable' ? const GarageEntitlementRead.unavailable() : status))));
      await tester.pump();await tester.pump(const Duration(milliseconds:50));
      expect(find.byType(GarageSandboxCheckoutCard),scenario=='fresh' ? findsOneWidget : findsNothing);
      expect(calls,0);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for(final raw in [
    {'entitlement':{'active':false,'source':null,'access_ends_at':null,'last_payment_state':null},'trial_available':true},
    {'active':false,'source':null,'access_ends_at':null,'last_payment_state':null},
    {'entitlement':{'active':false,'source':null,'access_ends_at':null,'last_payment_state':null},'trial_available':'true'},
  ]) {
    test('billing parser requires explicit boolean envelope: $raw',() async {
      final repo=GarageEntitlementRepository(enabled:true,billingStatus:true,
        supabaseUrl:'https://fyestmquqvkdebxxbcky.supabase.co',currentUserId:()=>actor,
        currentSessionKey:()=> 'synthetic',invoke:(_)async=>raw);
      final read=await repo.load(workspace);
      expect(read.trialAvailable,raw['trial_available']==true);
    });
  }
  test('completed billing hint expires on account replacement and requires a fresh read',() async {
    var user=actor;
    final repo=GarageEntitlementRepository(enabled:true,billingStatus:true,
      supabaseUrl:'https://fyestmquqvkdebxxbcky.supabase.co',
      currentUserId:()=>user,currentSessionKey:()=> 'synthetic',
      invoke:(_)async=>{'entitlement':{'active':false,'source':null,
        'access_ends_at':null,'last_payment_state':null},'trial_available':true});
    final read=await repo.load(workspace);
    expect(read.trialAvailable,isTrue);
    user='00000000-0000-4000-8000-000000000003';
    expect(read.trialAvailable,isFalse);
    expect(read.state,GarageEntitlementReadState.unavailable);
    user=actor;
    expect(read.trialAvailable,isFalse);
    expect((await repo.load(workspace)).trialAvailable,isTrue);
  });
  testWidgets('account switch after checkbox cannot dispatch using the previous hint',(tester) async {
    var user=actor;var calls=0;
    final statuses=GarageEntitlementRepository(enabled:true,billingStatus:true,
      supabaseUrl:'https://fyestmquqvkdebxxbcky.supabase.co',
      currentUserId:()=>user,currentSessionKey:()=> 'synthetic',
      invoke:(_)async=>{'entitlement':{'active':false,'source':null,
        'access_ends_at':null,'last_payment_state':null},'trial_available':true});
    final checkout=GarageCheckoutRepository(enabled:true,
      supabaseUrl:'https://fyestmquqvkdebxxbcky.supabase.co',
      currentUserId:()=>user,currentSessionKey:()=> 'synthetic',
      invoke:(_)async {calls++;return null;});
    await tester.pumpWidget(MaterialApp(home:GarageBillingScreen(
      workshopName:'Synthetic',workspaceId:workspace,isOwner:true,
      checkoutRepository:checkout,loadEntitlement:()=>statuses.load(workspace))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));await tester.pumpAndSettle();
    final button=find.widgetWithText(FilledButton,'Prepare test Checkout');
    await tester.ensureVisible(button);
    user='00000000-0000-4000-8000-000000000003';
    await tester.tap(button);await tester.pump();
    expect(calls,0);
  });

}
