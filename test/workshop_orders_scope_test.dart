import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/quote_order_repository.dart';
import 'package:fleetpilot/garage/workshop_quote_publisher.dart';
import 'package:fleetpilot/garage/workshop_quotes_screen.dart';
import 'garage_booking_screens_test.dart' as layout;
import 'workshop_quote_publish_intent_test.dart' as form;
import 'quote_editor_scope_test.dart' as editor;

void main() {
  setUp(() => AppLocale.language.value = 'en');
  for (final changed in ['orders', 'currency', 'publish']) {
    for (final fails in [false, true]) {
      testWidgets('$changed binding refreshes list and rejects stale result: failure=$fails', (tester) async {
        final pending = Completer<List<GarageQuoteOrder>>();
        StateSetter? rebuild;
        var loads = 0;
        var nextLoads = 0;
        final load = () { loads++; return loads == 1 ? pending.future : Future.value([editor.nextOrder]); };
        final currency = (String _) async => const GarageQuoteCurrencySelection('GBP', locked: false);
        final publish = (String _, String __, List<GarageQuoteDraftLine> ___) async => 1;
        Widget current = GarageWorkshopQuotesScreen(loadOrders: load, loadCurrency: currency, publish: publish);
        await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (_, setState) {
          rebuild = setState; return current;
        })));
        await tester.pump();
        current = GarageWorkshopQuotesScreen(
          loadOrders: changed == 'orders' ? () async { nextLoads++; return [editor.nextOrder]; } : load,
          loadCurrency: changed == 'currency'
            ? (_) async => const GarageQuoteCurrencySelection('EUR', locked: true) : currency,
          publish: changed == 'publish' ? (_, __, ___) async => 2 : publish);
        rebuild!(() {});
        await tester.pumpAndSettle();
        expect(find.text('New order'), findsOneWidget);
        if (fails) { pending.completeError(StateError('Synthetic old list failure')); }
        else { pending.complete([form.order]); }
        await tester.pumpAndSettle();
        expect(find.text('New order'), findsOneWidget);
        expect(find.byKey(Key('quote_order_${form.order.id}')), findsNothing);
        expect(find.byKey(const Key('quote_orders_error')), findsNothing);
        expect(loads + nextLoads, 2);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('single editor opening and stale list tap after return', (tester) async {
    var loads = 0;
    var currencies = 0;
    var writes = 0;
    await layout.render(tester, GarageWorkshopQuotesScreen(
      loadOrders: () async { loads++; return [form.order]; },
      loadCurrency: (_) async { currencies++; return const GarageQuoteCurrencySelection('GBP', locked: false); },
      publish: (_, __, ___) async { writes++; return 1; }));
    final tap = tester.widget<ListTile>(find.byKey(Key('quote_order_${form.order.id}'))).onTap!;
    tap(); tap();
    await tester.pumpAndSettle();
    expect(find.byType(GarageQuoteEditorScreen), findsOneWidget);
    expect(currencies, 1);
    Navigator.pop(tester.element(find.byType(GarageQuoteEditorScreen)));
    await tester.pumpAndSettle();
    expect(loads, 2);
    tap();
    await tester.pumpAndSettle();
    expect(find.byType(GarageQuoteEditorScreen), findsNothing);
    expect(currencies, 1);
    await tester.tap(find.byKey(Key('quote_order_${form.order.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(GarageQuoteEditorScreen), findsOneWidget);
    expect(currencies, 2);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });

  for (final disposed in [false, true]) {
    testWidgets('scope invalidation closes owned editor and confirmation: disposed=$disposed', (tester) async {
      StateSetter? rebuild;
      var oldLoads = 0;
      var nextLoads = 0;
      var oldCurrencies = 0;
      var nextCurrencies = 0;
      var writes = 0;
      Widget current = GarageWorkshopQuotesScreen(
        loadOrders: () async { oldLoads++; return [form.order]; },
        loadCurrency: (_) async { oldCurrencies++; return const GarageQuoteCurrencySelection('GBP', locked: false); },
        publish: (_, __, ___) async { writes++; return 1; });
      await layout.render(tester, StatefulBuilder(builder: (_, setState) {
        rebuild = setState; return current;
      }));
      final oldTap = tester.widget<ListTile>(find.byKey(Key('quote_order_${form.order.id}'))).onTap!;
      oldTap();
      await tester.pumpAndSettle();
      final boundEditor = tester.widget<GarageQuoteEditorScreen>(find.byType(GarageQuoteEditorScreen));
      await form.fill(tester);
      await tester.tap(find.byKey(const Key('quote_publish')));
      await tester.pumpAndSettle();
      final oldYes = tester.widget<FilledButton>(find.byKey(const Key('garage_editor_confirm'))).onPressed!;
      current = disposed ? const Scaffold(body: Text('Signed out')) : GarageWorkshopQuotesScreen(
        loadOrders: () async { nextLoads++; return [editor.nextOrder]; },
        loadCurrency: (_) async { nextCurrencies++; return const GarageQuoteCurrencySelection('EUR', locked: false); },
        publish: (_, __, ___) async { writes++; return 2; });
      rebuild!(() {});
      await tester.pumpAndSettle();
      expect(find.byType(GarageQuoteEditorScreen), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(disposed ? 'Signed out' : 'New order'), findsOneWidget);
      oldTap(); oldYes();
      await expectLater(boundEditor.loadCurrency(), throwsStateError);
      await expectLater(boundEditor.publish('GBP', const []), throwsStateError);
      await tester.pumpAndSettle();
      expect(oldLoads, 1);
      expect(nextLoads, disposed ? 0 : 1);
      expect(oldCurrencies, 1);
      expect(nextCurrencies, 0);
      expect(writes, 0);
      if (!disposed) {
        await tester.tap(find.byKey(Key('quote_order_${editor.nextOrder.id}')));
        await tester.pumpAndSettle();
        expect(nextCurrencies, 1);
        expect(find.byType(GarageQuoteEditorScreen), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final fails in [false, true]) {
    testWidgets('scope closes pending currency editor and ignores late result: failure=$fails', (tester) async {
      final pending = Completer<GarageQuoteCurrencySelection>();
      StateSetter? rebuild;
      var nextLoads = 0;
      Widget current = GarageWorkshopQuotesScreen(
        loadOrders: () async => [form.order], loadCurrency: (_) => pending.future,
        publish: (_, __, ___) async => 1);
      await layout.render(tester, StatefulBuilder(builder: (_, setState) {
        rebuild = setState; return current;
      }));
      await tester.tap(find.byKey(Key('quote_order_${form.order.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GarageQuoteEditorScreen), findsOneWidget);
      current = GarageWorkshopQuotesScreen(
        loadOrders: () async { nextLoads++; return [editor.nextOrder]; },
        loadCurrency: (_) async => const GarageQuoteCurrencySelection('EUR', locked: false),
        publish: (_, __, ___) async => 2);
      rebuild!(() {});
      await tester.pumpAndSettle();
      if (fails) { pending.completeError(StateError('Synthetic old currency failure')); }
      else { pending.complete(const GarageQuoteCurrencySelection('PLN', locked: true)); }
      await tester.pumpAndSettle();
      expect(find.byType(GarageQuoteEditorScreen), findsNothing);
      expect(find.text('New order'), findsOneWidget);
      expect(nextLoads, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
