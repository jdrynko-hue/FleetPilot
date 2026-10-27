import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/billing_screen.dart';
import 'package:fleetpilot/garage/checkout_card.dart';
import 'package:fleetpilot/garage/checkout_repository.dart';
import 'package:fleetpilot/garage/entitlement_repository.dart';
import 'package:fleetpilot/garage/paid_rejoin_text.dart';

void main() {
 const a='11111111-1111-4111-8111-111111111111';
 const w='22222222-2222-4222-8222-222222222222';
 const qa='https://fyestmquqvkdebxxbcky.supabase.co';
 const inactive={'active':false,'source':null,'access_ends_at':null,'last_payment_state':null};
 Map<String,Object?> envelope({bool paid=true,bool trial=false}) =>
  {'entitlement':inactive,'trial_available':trial,'paid_available':paid};
 GarageCheckoutRepository checkout({bool enabled=true,GarageCheckoutInvoke? invoke}) =>
  GarageCheckoutRepository(enabled:true,paidRejoinEnabled:enabled,supabaseUrl:qa,
   currentUserId:()=>a,currentSessionKey:()=> 'synthetic',invoke:invoke??(_)async=>
    {'mode':'test','session_id':'cs_test_paid','trial_days':0,'url':'https://checkout.stripe.com/c/pay/cs_test_paid#synthetic'});
 test('paid Checkout is separately enabled and rejects a new trial response',() async {
  final disabled=checkout(enabled:false);
  expect((await disabled.start(workspaceId:w,planCode:'pilot',billingInterval:'month',businessPurchaseConfirmed:true,paidRejoin:true)).state,GarageCheckoutState.unavailable);
  Map<String,Object>? sent;
  final repo=checkout(invoke:(body) async {sent=body;return {'mode':'test','session_id':'cs_test_paid','trial_days':7,'url':'https://checkout.stripe.com/c/pay/cs_test_paid'};});
  expect((await repo.start(workspaceId:w,planCode:'pilot',billingInterval:'month',businessPurchaseConfirmed:true,paidRejoin:true)).state,GarageCheckoutState.reconciliationRequired);
  expect(sent?['purchase_kind'],'paid_rejoin');
  expect(()=>GarageCheckoutResult.parse({'mode':'test','session_id':'cs_test_paid','trial_days':0,'url':'https://checkout.stripe.com/c/pay/cs_test_paid'}),throwsFormatException);
 });
 test('server paid eligibility is invalidated by session replacement',() async {
  var session='one';
  final repo=GarageEntitlementRepository(enabled:true,billingStatus:true,supabaseUrl:qa,
    currentUserId:()=>a,currentSessionKey:()=>session,invoke:(_)async=>envelope());
  final read=await repo.load(w);expect(read.paidAvailable,isTrue);expect(read.trialAvailable,isFalse);
  session='two';expect(read.paidAvailable,isFalse);session='one';expect(read.paidAvailable,isFalse);
 });
 test('contradictory free and paid eligibility fails closed',() async {
  final repo=GarageEntitlementRepository(enabled:true,billingStatus:true,supabaseUrl:qa,
    currentUserId:()=>a,currentSessionKey:()=> 'synthetic',invoke:(_)async=>envelope(trial:true));
  expect((await repo.load(w)).state,GarageEntitlementReadState.unavailable);
 });
 for(final mode in ['allowed','disabled','legacy','loading','error']) {
  testWidgets('paid offer requires an explicit fresh owner decision: $mode',(tester) async {
   final pending=Completer<GarageEntitlementRead>();
   final repo=checkout(enabled:mode!='disabled');
   final status=GarageEntitlementRead.verified(const GarageEntitlement(active:false),paidAvailable:mode!='legacy');
   await tester.pumpWidget(MaterialApp(home:GarageBillingScreen(workshopName:'Synthetic',workspaceId:w,isOwner:true,
    checkoutRepository:repo,loadEntitlement:()=> mode=='loading'?pending.future:Future.value(mode=='error'?const GarageEntitlementRead.unavailable():status))));
   await tester.pump();await tester.pump(const Duration(milliseconds:50));
   expect(find.byType(GarageSandboxCheckoutCard),mode=='allowed'?findsOneWidget:findsNothing);
   if(mode=='allowed')expect(find.text(GaragePaidRejoinText.get(1)),findsOneWidget);
   await tester.pumpWidget(const SizedBox());
  });
 }
 testWidgets('paid card dispatches only after business confirmation and never announces a new trial',(tester) async {
  Map<String,Object>? sent;
  final repo=checkout(invoke:(body) async {sent=body;return {'mode':'test','session_id':'cs_test_paid','trial_days':0,'url':'https://checkout.stripe.com/c/pay/cs_test_paid'};});
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:GarageSandboxCheckoutCard(repository:repo,workspaceId:w,isOwner:true,paidRejoin:true))));
  expect(find.text(GaragePaidRejoinText.get(0)),findsOneWidget);
  expect(sent,isNull);
  await tester.tap(find.byType(CheckboxListTile));await tester.pump();
  final prepare=find.widgetWithText(FilledButton,'Prepare test Checkout');await tester.ensureVisible(prepare);await tester.tap(prepare);await tester.pumpAndSettle();
  expect(sent?['purchase_kind'],'paid_rejoin');expect(find.widgetWithText(FilledButton,'Open test Checkout'),findsOneWidget);
 });
}
