import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/quote_currency_picker.dart';
import 'package:fleetpilot/garage/quote_order_repository.dart';
import 'package:fleetpilot/garage/workshop_quotes_screen.dart';
import 'package:fleetpilot/garage/workshop_quote_publisher.dart';
import 'garage_booking_screens_test.dart' as layout;
import 'workshop_quote_publish_intent_test.dart' as form;

const nextOrder = GarageQuoteOrder(id: '00000000-0000-4000-8000-000000000002',
  complaint: 'New order', status: 'awaiting_approval');

void main() {
  setUp(() => AppLocale.language.value = 'en');
  for (final fails in [false, true]) {
    testWidgets('old currency response cannot replace current scope: failure=$fails', (tester) async {
      final old = Completer<GarageQuoteCurrencySelection>();
      StateSetter? rebuild;
      final publish = (String _, List<GarageQuoteDraftLine> __) async => 1;
      Widget current = GarageQuoteEditorScreen(order: form.order,
        loadCurrency: () => old.future, publish: publish);
      await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (_, setState) {
        rebuild = setState; return current;
      })));
      await tester.pump();
      current = GarageQuoteEditorScreen(order: nextOrder,
        loadCurrency: () async => const GarageQuoteCurrencySelection('EUR', locked: false),
        publish: publish);
      rebuild!(() {});
      await tester.pumpAndSettle();
      if (fails) { old.completeError(StateError('Synthetic old currency failure')); }
      else { old.complete(const GarageQuoteCurrencySelection('PLN', locked: true)); }
      await tester.pumpAndSettle();
      expect(tester.widget<GarageQuoteCurrencyPicker>(find.byType(GarageQuoteCurrencyPicker)).currency, 'EUR');
      expect(find.text('New order'), findsOneWidget);
      expect(find.byKey(const Key('quote_editor_error')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final changed in ['order', 'load', 'publish']) {
    testWidgets('$changed scope change clears draft and invalidates open confirmation', (tester) async {
      StateSetter? rebuild;
      var oldWrites = 0;
      var newWrites = 0;
      final load = () async => const GarageQuoteCurrencySelection('GBP', locked: false);
      final publish = (String _, List<GarageQuoteDraftLine> __) async { oldWrites++; return 1; };
      final nextPublish = (String _, List<GarageQuoteDraftLine> __) async { newWrites++; return 2; };
      Widget current = GarageQuoteEditorScreen(order: form.order,
        loadCurrency: load, publish: publish);
      await layout.render(tester, StatefulBuilder(builder: (_, setState) {
        rebuild = setState; return current;
      }));
      final oldCurrency = tester.widget<GarageQuoteCurrencyPicker>(find.byType(GarageQuoteCurrencyPicker)).onChanged;
      final oldType = tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('quote_type_0'))).onChanged!;
      await form.fill(tester);
      final oldAdd = tester.widget<OutlinedButton>(find.byKey(const Key('quote_add_line'))).onPressed!;
      final oldRequest = tester.widget<FilledButton>(find.byKey(const Key('quote_publish'))).onPressed!;
      oldRequest();
      await tester.pumpAndSettle();
      final oldYes = tester.widget<FilledButton>(find.byKey(const Key('garage_editor_confirm'))).onPressed!;
      current = GarageQuoteEditorScreen(order: changed == 'order' ? nextOrder : form.order,
        loadCurrency: changed == 'load'
          ? () async => const GarageQuoteCurrencySelection('EUR', locked: false) : load,
        publish: changed == 'publish' ? nextPublish : publish);
      rebuild!(() {});
      await tester.pumpAndSettle();
      oldYes();
      await tester.pumpAndSettle();
      expect(oldWrites, 0); expect(newWrites, 0);
      oldCurrency('PLN'); oldType('part'); oldAdd(); oldRequest();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final picker = tester.widget<GarageQuoteCurrencyPicker>(find.byType(GarageQuoteCurrencyPicker));
      expect(picker.currency, changed == 'load' ? 'EUR' : 'GBP');
      expect(tester.widget<TextField>(find.byKey(const Key('quote_description_0'))).controller!.text, isEmpty);
      expect(tester.widget<TextField>(find.byKey(const Key('quote_unit_0'))).controller!.text, isEmpty);
      expect(tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('quote_type_0'))).initialValue, 'labour');
      expect(find.byKey(const Key('quote_draft_1')), findsNothing);
      await form.fill(tester);
      await tester.tap(find.byKey(const Key('quote_publish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('garage_editor_confirm')));
      await tester.pumpAndSettle();
      expect(oldWrites, changed == 'publish' ? 0 : 1);
      expect(newWrites, changed == 'publish' ? 1 : 0);
      expect(find.byKey(const Key('quote_editor_success')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final fails in [false, true]) {
    testWidgets('old publication cannot finish current publication: failure=$fails', (tester) async {
      final old = Completer<int>();
      final next = Completer<int>();
      StateSetter? rebuild;
      var oldWrites = 0;
      var newWrites = 0;
      Widget current = GarageQuoteEditorScreen(order: form.order,
        loadCurrency: () async => const GarageQuoteCurrencySelection('GBP', locked: false),
        publish: (_, __) { oldWrites++; return old.future; });
      await layout.render(tester, StatefulBuilder(builder: (_, setState) {
        rebuild = setState; return current;
      }));
      await form.fill(tester);
      await tester.tap(find.byKey(const Key('quote_publish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('garage_editor_confirm')));
      await tester.pumpAndSettle();
      current = GarageQuoteEditorScreen(order: nextOrder,
        loadCurrency: () async => const GarageQuoteCurrencySelection('EUR', locked: false),
        publish: (_, __) { newWrites++; return next.future; });
      rebuild!(() {});
      await tester.pumpAndSettle();
      await form.fill(tester);
      await tester.tap(find.byKey(const Key('quote_publish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('garage_editor_confirm')));
      await tester.pumpAndSettle();
      if (fails) { old.completeError(TimeoutException('Synthetic old publication failure')); }
      else { old.complete(99); }
      await tester.pumpAndSettle();
      expect(oldWrites, 1); expect(newWrites, 1);
      expect(find.byKey(const Key('quote_editor_success')), findsNothing);
      expect(find.byKey(const Key('quote_editor_error')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('quote_publish'))).onPressed, isNull);
      next.complete(2);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quote_editor_success')), findsOneWidget);
      expect(find.textContaining('99'), findsNothing);
      expect(oldWrites, 1); expect(newWrites, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
