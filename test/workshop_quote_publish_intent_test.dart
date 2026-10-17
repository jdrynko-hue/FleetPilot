import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/quote_currency_picker.dart';
import 'package:fleetpilot/garage/quote_order_repository.dart';
import 'package:fleetpilot/garage/workshop_quotes_screen.dart';
import 'package:fleetpilot/garage/workshop_quote_publisher.dart';
import 'garage_booking_screens_test.dart' as layout;

const order = GarageQuoteOrder(id: '00000000-0000-4000-8000-000000000001',
  complaint: 'Brakes', status: 'diagnosing');

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('quote_description_0')), 'Pads');
  await tester.enterText(find.byKey(const Key('quote_unit_0')), '20.25');
  await tester.ensureVisible(find.byKey(const Key('quote_publish')));
  await tester.drag(find.byType(ListView), const Offset(0, -200));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppLocale.language.value = 'en');
  for (final decision in <bool?>[true, false, null]) {
    testWidgets('publication has one confirmation and one decision: $decision', (tester) async {
      var writes = 0;
      final screen = GarageQuoteEditorScreen(order: order,
        loadCurrency: () async => const GarageQuoteCurrencySelection('GBP', locked: false),
        publish: (_, __) async { writes++; return 2; });
      await layout.render(tester, Builder(builder: (context) => Scaffold(body:
        TextButton(key: const Key('open_editor'), onPressed: () =>
          Navigator.push<void>(context, MaterialPageRoute(builder: (_) => screen)),
          child: const Text('Home')))));
      await tester.tap(find.byKey(const Key('open_editor')));
      await tester.pumpAndSettle();
      await fill(tester);
      final request = tester.widget<FilledButton>(find.byKey(const Key('quote_publish'))).onPressed!;
      request(); request();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(writes, 0);
      final yes = tester.widget<FilledButton>(find.byKey(const Key('garage_editor_confirm'))).onPressed!;
      final no = tester.widget<TextButton>(find.descendant(of: find.byType(AlertDialog),
        matching: find.byType(TextButton))).onPressed!;
      if (decision == null) {
        Navigator.pop(tester.element(find.byType(AlertDialog)));
      } else {
        (decision ? yes : no)();
      }
      yes(); no(); yes();
      await tester.pumpAndSettle();
      expect(writes, decision == true ? 1 : 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(GarageQuoteEditorScreen), findsOneWidget);
      expect(find.byKey(const Key('open_editor')), findsNothing);
      if (decision != true) {
        request();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        yes(); no();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(writes, 0);
        Navigator.pop(tester.element(find.byType(AlertDialog)));
        await tester.pumpAndSettle();
      }
      showDialog<void>(context: tester.element(find.byType(GarageQuoteEditorScreen)),
        builder: (_) => const AlertDialog(key: Key('later_editor_dialog'), title: Text('Later')));
      await tester.pumpAndSettle();
      yes(); no();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('later_editor_dialog')), findsOneWidget);
      expect(writes, decision == true ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending publication freezes fields and rejects cached edits before uncertain result', (tester) async {
    final pending = Completer<int>();
    var writes = 0;
    String? savedCurrency;
    List<GarageQuoteDraftLine>? saved;
    await layout.render(tester, GarageQuoteEditorScreen(order: order,
      loadCurrency: () async => const GarageQuoteCurrencySelection('GBP', locked: false),
      publish: (currency, lines) {
        writes++; savedCurrency = currency; saved = lines; return pending.future;
      }));
    final changeCurrency = tester.widget<GarageQuoteCurrencyPicker>(find.byType(GarageQuoteCurrencyPicker)).onChanged;
    final changeType = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('quote_type_0'))).onChanged!;
    await fill(tester);
    final add = tester.widget<OutlinedButton>(find.byKey(const Key('quote_add_line'))).onPressed!;
    final request = tester.widget<FilledButton>(find.byKey(const Key('quote_publish'))).onPressed!;
    request();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_editor_confirm')));
    await tester.pumpAndSettle();
    expect(writes, 1);
    changeCurrency('PLN'); changeType('part'); add(); request();
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(savedCurrency, 'GBP');
    expect(saved!.single.type, 'labour');
    expect(saved!.single.unitPriceMinor, 2025);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.widget<GarageQuoteCurrencyPicker>(find.byType(GarageQuoteCurrencyPicker)).enabled, isFalse);
    expect(tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('quote_type_0'))).onChanged, isNull);
    for (final field in ['description', 'quantity', 'unit', 'tax']) {
      expect(tester.widget<TextField>(find.byKey(Key('quote_${field}_0'))).enabled, isFalse);
    }
    pending.completeError(TimeoutException('Synthetic uncertain publication'));
    await tester.pumpAndSettle();
    request(); changeCurrency('EUR'); changeType('other'); add();
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.byKey(const Key('quote_editor_error')), findsOneWidget);
    expect(find.byKey(const Key('quote_publish')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
