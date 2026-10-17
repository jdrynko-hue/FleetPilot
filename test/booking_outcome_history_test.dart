import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/ecosystem/customer_portal.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';
import 'garage_booking_screens_test.dart' as fixture;
import 'garage_booking_request_locales_test.dart' as fields;

void main() {
  tearDown(() => AppLocale.language.value = 'en');
  for (final uncertain in [false, true]) {
    testWidgets('booking outcome opens current history once without replay (uncertain=$uncertain)', (tester) async {
      AppLocale.language.value = uncertain ? 'en' : 'pl';
      final pending = Completer<String>();
      var writes = 0, searches = 0, historyBuilds = 0, notificationBuilds = 0;
      final BookingSearch search = ({city}) async { searches++; return [fixture.shop]; };
      final BookingSubmit submit = ({required workspaceId, required customerName,
        required vehicleMake, required vehicleModel, required service, required concern,
        required desiredStart, required requestKey, registration}) {
        writes++; return pending.future;
      };
      final BookingTimePicker picker = (_) async => DateTime.now().add(const Duration(days: 2));
      await fixture.render(tester, CustomerPortal(searchFirst: true,
        searchPage: (_, showBookings) => GarageBookingSearchScreen(search: search,
          submit: submit, pickTime: picker, onViewBookings: showBookings),
        pages: [(_) => const SizedBox(), (_) {
          historyBuilds++; return const Text('Current account history');
        }, (_) { notificationBuilds++; return const Text('Notifications'); }]));
      expect(historyBuilds, 0);
      await fields.tap(tester, 'booking_search_submit');
      await fields.tap(tester, 'booking_open_${fixture.shop.workspaceId}');
      await fields.completeRequest(tester);
      await fields.tap(tester, 'booking_send');
      expect(writes, 1);
      expect(historyBuilds, 0);
      expect(find.byKey(const Key('booking_view_bookings')), findsNothing);
      if (uncertain) {
        pending.completeError(TimeoutException('Synthetic uncertain outcome'));
      } else {
        pending.complete(fixture.bookingId);
      }
      await tester.pumpAndSettle();
      await fields.reveal(tester, 'booking_view_bookings');
      final history = find.byKey(const Key('booking_view_bookings'));
      final staleAction = tester.widget<OutlinedButton>(history).onPressed!;
      final done = uncertain ? null : tester.widget<OutlinedButton>(
        find.byKey(const Key('booking_done'))).onPressed;
      await tester.tap(history);
      staleAction(); done?.call();
      await tester.pumpAndSettle();
      expect(find.text('Current account history'), findsOneWidget);
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);
      expect(historyBuilds, 1);
      expect(notificationBuilds, 0);
      expect(searches, 1);
      expect(writes, 1);
      staleAction();
      await tester.pumpAndSettle();
      expect(historyBuilds, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('old request exit cannot navigate a replacement directory scope', (tester) async {
    var oldHistory = 0, newHistory = 0, searches = 0;
    late StateSetter replace;
    VoidCallback history = () => oldHistory++;
    final BookingSearch search = ({city}) async { searches++; return [fixture.shop]; };
    final BookingSubmit submit = ({required workspaceId, required customerName,
      required vehicleMake, required vehicleModel, required service, required concern,
      required desiredStart, required requestKey, registration}) async => fixture.bookingId;
    final BookingTimePicker picker = (_) async => DateTime.now().add(const Duration(days: 2));
    await fixture.render(tester, StatefulBuilder(builder: (_, setState) {
      replace = setState;
      return GarageBookingSearchScreen(search: search, submit: submit,
        pickTime: picker, onViewBookings: history);
    }));
    await fields.tap(tester, 'booking_search_submit');
    await fields.tap(tester, 'booking_open_${fixture.shop.workspaceId}');
    replace(() => history = () => newHistory++);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(GarageBookingRequestScreen)))
      .pop(BookingRequestExit.bookings);
    await tester.pumpAndSettle();
    expect(oldHistory, 0);
    expect(newHistory, 0);
    expect(searches, 1);
    expect(tester.takeException(), isNull);
  });
}
