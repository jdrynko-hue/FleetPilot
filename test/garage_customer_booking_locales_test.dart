import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_management_screens.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'garage_booking_screens_test.dart' as fixture;

Future<void> cancelDialog(WidgetTester tester) async {
  final button = find.byKey(Key('customer_booking_cancel_${fixture.bookingId}'));
  await tester.scrollUntilVisible(button, 150,
    scrollable: find.byType(Scrollable).first);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppLocale.language.value = 'en');
  for (final locale in supportedLanguages) {
    for (final initial in [GarageBookingStatus.requested, GarageBookingStatus.confirmed]) {
      testWidgets('customer cancellation preserves $initial semantics at 320px in $locale', (tester) async {
        AppLocale.language.value = locale;
        var status = initial;
        var calls = 0;
        final terminal = initial == GarageBookingStatus.requested
          ? GarageBookingStatus.withdrawn : GarageBookingStatus.cancellationRequested;
        await fixture.render(tester, GarageMyBookingsScreen(
          loadBookings: () async => [fixture.myRequest(status: status)],
          cancel: (id) async {
            expect(id, fixture.bookingId);
            calls++;
            status = terminal;
            return terminal;
          }), width: 320);
        expect(find.text(GarageUiText.get('customerBookingsTitle')), findsOneWidget);
        expect(find.text(GarageUiText.get('customerBookingsDisclaimer')), findsOneWidget);
        expect(find.byTooltip(GarageUiText.get('refresh')), findsOneWidget);
        await cancelDialog(tester);
        expect(find.text(GarageUiText.get(initial == GarageBookingStatus.requested
          ? 'customerWithdrawQuestion' : 'customerRequestCancelQuestion')), findsOneWidget);
        await tester.tap(find.text(GarageUiText.get('customerCancelNo')));
        await tester.pumpAndSettle();
        expect(calls, 0);
        await cancelDialog(tester);
        await tester.tap(find.byKey(const Key('customer_booking_confirm_cancel')));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(status, terminal);
        expect(find.byKey(Key('customer_booking_cancel_${fixture.bookingId}')), findsNothing);
        expect(find.byKey(const Key('customer_booking_error')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('uncertain cancellation reloads status before further actions in $locale', (tester) async {
      AppLocale.language.value = locale;
      var loads = 0;
      var calls = 0;
      await fixture.render(tester, GarageMyBookingsScreen(
        loadBookings: () async {
          loads++;
          return [fixture.myRequest(status: loads == 1
            ? GarageBookingStatus.confirmed : GarageBookingStatus.cancellationRequested)];
        },
        cancel: (_) async {
          calls++;
          throw TimeoutException('Synthetic uncertain cancellation');
        }), width: 320);
      await cancelDialog(tester);
      await tester.tap(find.byKey(const Key('customer_booking_confirm_cancel')));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(calls, 1);
      expect(tester.widget<Text>(find.byKey(const Key('customer_booking_error'))).data,
        GarageUiText.get('customerCancelUnconfirmed'));
      expect(find.byKey(Key('customer_booking_cancel_${fixture.bookingId}')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('private booking load failure uses current locale in $locale', (tester) async {
      AppLocale.language.value = locale;
      await fixture.render(tester, GarageMyBookingsScreen(
        loadBookings: () async => throw StateError('Synthetic access failure'),
        cancel: (_) async => GarageBookingStatus.withdrawn), width: 320);
      expect(tester.widget<Text>(find.byKey(const Key('customer_booking_error'))).data,
        GarageUiText.get('customerBookingsLoadFailed'));
      expect(find.byKey(const Key('customer_booking_empty')), findsNothing);
      expect(find.byKey(Key('customer_booking_item_${fixture.bookingId}')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
