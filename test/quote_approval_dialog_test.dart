import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/customer_quote_screen.dart';
import 'garage_customer_quote_screen_test.dart' as fixture;
import 'garage_booking_screens_test.dart' as layout;

void main() {
  setUp(() => AppLocale.language.value = 'en');
  for (final decision in <bool?>[true, false, null]) {
    testWidgets('quote approval has one dialog and one decision: $decision', (tester) async {
      var approvals = 0;
      var loads = 0;
      final revisions = <int>[];
      final screen = GarageCustomerQuoteScreen(
        loadQuote: () async { loads++; return fixture.quote(revision: 7); },
        approveRevision: (revision) async {
          approvals++;
          revisions.add(revision);
          return revision;
        });
      await layout.render(tester, Builder(builder: (context) => Scaffold(
        body: TextButton(key: const Key('open_quote'), onPressed: () =>
          Navigator.push<void>(context, MaterialPageRoute(builder: (_) => screen)),
          child: const Text('Home')))));
      await tester.tap(find.byKey(const Key('open_quote')));
      await tester.pumpAndSettle();
      final request = tester.widget<FilledButton>(
        find.byKey(const Key('garage_quote_approve'))).onPressed!;
      request(); request();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(approvals, 0);
      expect(loads, 1);
      final yes = tester.widget<FilledButton>(
        find.byKey(const Key('garage_quote_confirm'))).onPressed!;
      final no = tester.widget<TextButton>(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextButton))).onPressed!;
      if (decision == null) {
        Navigator.pop(tester.element(find.byType(AlertDialog)));
      } else {
        (decision ? yes : no)();
      }
      yes(); no(); yes();
      await tester.pumpAndSettle();
      expect(approvals, decision == true ? 1 : 0);
      expect(revisions, decision == true ? [7] : isEmpty);
      expect(loads, decision == true ? 2 : 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(GarageCustomerQuoteScreen), findsOneWidget);
      expect(find.byKey(const Key('open_quote')), findsNothing);
      if (decision != true) {
        // Cancellation releases the opening lock for a fresh explicit intent.
        request();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        yes(); no();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(approvals, 0);
        Navigator.pop(tester.element(find.byType(AlertDialog)));
        await tester.pumpAndSettle();
      }
      final context = tester.element(find.byType(GarageCustomerQuoteScreen));
      showDialog<void>(context: context, builder: (_) => const AlertDialog(
        key: Key('later_quote_dialog'), title: Text('Later')));
      await tester.pumpAndSettle();
      yes(); no();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('later_quote_dialog')), findsOneWidget);
      expect(approvals, decision == true ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }
}
