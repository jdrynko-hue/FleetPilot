import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/entitlement_repository.dart';
import 'package:fleetpilot/garage/operation_access_notice.dart';
import 'package:fleetpilot/garage/quote_order_repository.dart';
import 'package:fleetpilot/garage/workshop_quotes_screen.dart';

void main() {
  tearDown(() => AppLocale.language.value = 'en');
  testWidgets('notice handles loading, inactive and narrow mobile width', (t) async {
    AppLocale.language.value = 'pl';
    t.view.physicalSize = const Size(320,640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final future = Completer<GarageEntitlementRead>();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      GarageOperationAccessNotice(scopeId:'shop',load:() => future.future),
    ]))));
    expect(find.byType(CircularProgressIndicator),findsOneWidget);
    future.complete(const GarageEntitlementRead.verified(GarageEntitlement(active:false)));
    await t.pumpAndSettle();
    expect(find.textContaining('Dostęp ograniczony'),findsOneWidget);
    expect(t.takeException(),isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('active notice expires and masks changed session context', (t) async {
    var now = DateTime.utc(2030);
    var current = true;
    final read = GarageEntitlementRead.verified(GarageEntitlement(active:true,
      source:GarageEntitlementSource.paid,accessEndsAt:now.add(const Duration(seconds:2))),
      contextCurrent:() => current);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: GarageOperationAccessNotice(
      scopeId:'shop',load:() async => read,now:() => now))));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('garage_operation_notice')),findsNothing);
    now = now.add(const Duration(seconds:2));
    await t.pump(const Duration(seconds:2));
    expect(find.textContaining('Limited access'),findsOneWidget);
    current = false;
    await t.pump(const Duration(seconds:30));
    expect(find.textContaining('Subscription not verified'),findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('old workspace read cannot replace new unavailable result', (t) async {
    final old = Completer<GarageEntitlementRead>();
    Widget screen(String scope,Future<GarageEntitlementRead> Function() load) =>
      MaterialApp(home:Scaffold(body:GarageOperationAccessNotice(scopeId:scope,load:load)));
    await t.pumpWidget(screen('old',() => old.future));
    await t.pumpWidget(screen('new',() async => throw StateError('unavailable')));
    await t.pumpAndSettle();
    old.complete(GarageEntitlementRead.verified(GarageEntitlement(active:true,
      source:GarageEntitlementSource.trial,accessEndsAt:DateTime.now().add(const Duration(days:1)))));
    await t.pumpAndSettle();
    expect(find.textContaining('Subscription not verified'),findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('generic existing repair requires confirmation and refreshes status', (t) async {
    var status = 'in_progress', writes = 0;
    await t.pumpWidget(MaterialApp(home:GarageWorkshopQuotesScreen(
      loadOrders:() async => [GarageQuoteOrder(id:'order',complaint:'Existing repair',status:status)],
      loadCurrency:(_) async => const GarageQuoteCurrencySelection('GBP',locked:true),
      publish:(_,__,___) async => throw StateError('must not publish'),
      finish:(id,target) async { expect(id,'order'); writes++; status=target; return target; },
    )));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('garage_finish_order')));
    await t.pumpAndSettle();
    expect(writes,0);
    await t.tap(find.byKey(const Key('garage_finish_confirm')));
    await t.pumpAndSettle();
    expect(writes,1); expect(status,'ready');
    expect(find.byKey(const Key('garage_finish_order')),findsOneWidget);
  });
  testWidgets('completion dialog is dismissed on workspace replacement', (t) async {
    var writes = 0;
    Widget screen(String name) => MaterialApp(home:GarageWorkshopQuotesScreen(
      loadOrders:() async => [GarageQuoteOrder(id:name,complaint:name,status:'in_progress')],
      loadCurrency:(_) async => const GarageQuoteCurrencySelection('GBP',locked:true),
      publish:(_,__,___) async => 1,
      finish:(_,target) async { writes++; return target; },
    ));
    await t.pumpWidget(screen('old'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('garage_finish_old')));
    await t.pumpAndSettle();
    await t.pumpWidget(screen('new'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('garage_finish_confirm')),findsNothing);
    expect(writes,0);
    expect(find.byKey(const Key('garage_finish_new')),findsOneWidget);
    expect(t.takeException(),isNull);
  });
}
