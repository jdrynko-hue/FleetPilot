import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/paid_renewal_repository.dart';
import 'package:fleetpilot/garage/paid_renewal_control.dart';
import 'package:fleetpilot/garage/paid_renewal_text.dart';
import 'package:fleetpilot/garage/billing_screen.dart';
import 'package:fleetpilot/garage/entitlement_repository.dart';
import 'package:fleetpilot/core/app_config.dart';
import 'package:fleetpilot/core/localization.dart';
void main(){
 const a='00000000-0000-4000-8000-000000000101',w='00000000-0000-4000-8000-000000000201';
 final end=DateTime.now().toUtc().add(const Duration(days:20));
 Map<String,Object> payload({bool stopping=false})=>{'status':stopping?'stopping':'renewing','access_ends_at':end.toIso8601String()};
 GaragePaidRenewalRepository repo({bool enabled=true,String? url,Future<Object?> Function(Map<String,Object>)? invoke,
 String? Function()? actor,String? Function()? session})=>GaragePaidRenewalRepository(enabled:enabled,
  supabaseUrl:url??'https://fyestmquqvkdebxxbcky.supabase.co',currentUserId:actor??()=>a,currentSessionKey:session??()=> 'fixture',
  invoke:invoke??(_)async=>payload());
 setUp(()=>AppLocale.language.value='en');
 test('new client gate stays off by default',()=>expect(AppConfig.garagePaidRenewalEnabled,isFalse));
 test('repository validates status, UTC date and no private response fields',()async{
  expect((await repo().request(w))?.stopping,isFalse);
  for(final value in [<String,Object>{...payload(),'subscription_id':'sub_private'},
   {'status':'canceled','access_ends_at':end.toIso8601String()},
   {'status':'renewing','access_ends_at':'2030-01-01'},
   {'status':'renewing','access_ends_at':DateTime.now().toUtc().subtract(const Duration(seconds:1)).toIso8601String()}]){
   expect(await repo(invoke:(_)async=>value).request(w),isNull);
  }
 });
 test('disabled and foreign backends dispatch nothing',()async{
  var calls=0;
  for(final r in [repo(enabled:false,invoke:(_)async{calls++;return payload();}),repo(url:'https://production.example.test',invoke:(_)async{calls++;return payload();})]){
   expect(await r.request(w,stop:true),isNull);
  }expect(calls,0);
 });
 test('account replacement while awaiting response invalidates result',()async{
  var actor=a;final pending=Completer<Object?>();
  final r=repo(actor:()=>actor,invoke:(_)=>pending.future);final future=r.request(w);
  actor=w;pending.complete(payload());expect(await future,isNull);
 });
 test('stop cannot accept renewing acknowledgement',()async=>expect(await repo().request(w,stop:true),isNull));
 for(final scenario in ['paid owner','trial','inactive','member','error','loading']){
  testWidgets('renewal control shown only for verified paid owner: $scenario',(tester)async{
   final pending=Completer<GarageEntitlementRead>();
   final read=scenario=='error'?const GarageEntitlementRead.unavailable():GarageEntitlementRead.verified(
    GarageEntitlement(active:scenario!='inactive',source:scenario=='trial'?GarageEntitlementSource.trial:scenario=='inactive'?null:GarageEntitlementSource.paid,
     accessEndsAt:scenario=='inactive'?null:end));
   await tester.pumpWidget(MaterialApp(home:GarageBillingScreen(workshopName:'Synthetic',workspaceId:w,isOwner:scenario!='member',
    paidRenewalRepository:repo(),loadEntitlement:()=>scenario=='loading'?pending.future:Future.value(read))));
   await tester.pump();await tester.pump(const Duration(milliseconds:20));
   expect(find.byType(GaragePaidRenewalControl),scenario=='paid owner'?findsOneWidget:findsNothing);
   await tester.pumpWidget(const SizedBox());
  });
 }
 testWidgets('explicit confirmation stops renewal once and preserves paid expiry',(tester)async{
  final calls=<String>[];
  final r=repo(invoke:(body)async{calls.add(body['action']! as String);return payload(stopping:body['action']=='stop');});
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:GaragePaidRenewalControl(repository:r,workspaceId:w,canManage:()=>true))));
  await tester.pumpAndSettle();expect(calls,['status']);
  await tester.tap(find.text(GaragePaidRenewalText.get(0)));await tester.pumpAndSettle();
  expect(calls,['status']);await tester.tap(find.text(GaragePaidRenewalText.get(3)));await tester.pumpAndSettle();
  expect(calls,['status','stop']);expect(find.textContaining('Renewal stop confirmed.'),findsOneWidget);
  expect(find.text(GaragePaidRenewalText.get(0)),findsNothing);
 });
 testWidgets('changed session inside dialog cannot dispatch stop',(tester)async{
  var session='one';final calls=<String>[];
  final r=repo(session:()=>session,invoke:(body)async{calls.add(body['action']! as String);return payload();});
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:GaragePaidRenewalControl(repository:r,workspaceId:w,canManage:()=>true))));
  await tester.pumpAndSettle();await tester.tap(find.text(GaragePaidRenewalText.get(0)));await tester.pumpAndSettle();
  session='two';await tester.tap(find.text(GaragePaidRenewalText.get(3)));await tester.pumpAndSettle();expect(calls,['status']);
 });
 testWidgets('uncertain mutation is not announced as stopping and never auto-retries',(tester)async{
  final calls=<String>[];
  final r=repo(invoke:(b)async{calls.add(b['action']! as String);if(b['action']=='stop')throw StateError('Unknown');return payload();});
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:GaragePaidRenewalControl(repository:r,workspaceId:w,canManage:()=>true))));
  await tester.pumpAndSettle();await tester.tap(find.text(GaragePaidRenewalText.get(0)));await tester.pumpAndSettle();
  await tester.tap(find.text(GaragePaidRenewalText.get(3)));await tester.pumpAndSettle();
  expect(calls,['status','stop']);expect(find.text(GaragePaidRenewalText.get(5)),findsOneWidget);
 });
 testWidgets('13 languages render at a 320px browser width',(tester)async{
  tester.view.physicalSize=const Size(320,720);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  for(final lang in GaragePaidRenewalText.values.keys){AppLocale.language.value=lang;
   expect(GaragePaidRenewalText.values[lang]!.length,8);
   await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:GaragePaidRenewalControl(
    key:ValueKey(lang),repository:repo(),workspaceId:w,canManage:()=>true)))));
   await tester.pumpAndSettle();expect(tester.takeException(),isNull);
  }
 });
}
