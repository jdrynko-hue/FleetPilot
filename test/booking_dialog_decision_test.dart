import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_management_screens.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'garage_booking_screens_test.dart' as fixture;

void main() {
  setUp(() => AppLocale.language.value = 'en');
  for (final operation in ['accept', 'decline', 'cancel', 'customer']) {
    for (final decision in <bool?>[true, false, null]) {
      testWidgets('$operation dialog accepts only one current decision: $decision', (tester) async {
        var writes = 0;
        final customer = operation == 'customer';
        final screen = customer
          ? GarageMyBookingsScreen(
              loadBookings: () async => [fixture.myRequest()],
              cancel: (_) async { writes++; return GarageBookingStatus.withdrawn; })
          : GarageBookingWorkshopScreen(
              loadInbox: () async => [fixture.workshopRequest(status: operation == 'cancel'
                ? GarageBookingStatus.cancellationRequested : GarageBookingStatus.requested)],
              respond: (_, accept) async {
                writes++;
                return accept ? GarageBookingStatus.confirmed : GarageBookingStatus.declined;
              },
              confirmCancellation: (_) async { writes++; });
        await fixture.render(tester, Builder(builder: (context) => Scaffold(
          body: TextButton(key: const Key('open_bookings'), onPressed: () =>
            Navigator.push<void>(context, MaterialPageRoute(builder: (_) => screen)),
            child: const Text('Home')))));
        await tester.tap(find.byKey(const Key('open_bookings')));
        await tester.pumpAndSettle();
        final action = customer ? 'customer_booking_cancel_${fixture.bookingId}'
          : 'workshop_booking_${operation}_${fixture.bookingId}';
        await tester.tap(find.byKey(Key(action)));
        await tester.pumpAndSettle();
        final yes = tester.widget<FilledButton>(find.byKey(Key(customer
          ? 'customer_booking_confirm_cancel' : 'workshop_booking_confirm'))).onPressed!;
        final no = tester.widget<TextButton>(find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextButton))).onPressed!;
        final dialogContext = tester.element(find.byType(AlertDialog));
        if (decision == null) {
          Navigator.pop(dialogContext);
        } else {
          (decision ? yes : no)();
        }
        // Reuse callbacks before the first dismissal has finished animating.
        yes(); no(); yes();
        await tester.pumpAndSettle();
        expect(writes, decision == true ? 1 : 0);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byKey(const Key('open_bookings')), findsNothing);
        expect(find.byType(GarageMyBookingsScreen), customer ? findsOneWidget : findsNothing);
        expect(find.byType(GarageBookingWorkshopScreen), customer ? findsNothing : findsOneWidget);
        // Disposed callbacks must not close a later unrelated modal either.
        final context = tester.element(find.byType(customer
          ? GarageMyBookingsScreen : GarageBookingWorkshopScreen));
        showDialog<void>(context: context, builder: (_) => const AlertDialog(
          key: Key('later_dialog'), title: Text('Later dialog')));
        await tester.pumpAndSettle();
        yes(); no();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('later_dialog')), findsOneWidget);
        expect(writes, decision == true ? 1 : 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
