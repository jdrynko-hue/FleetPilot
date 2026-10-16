import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_management_screens.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'garage_booking_screens_test.dart' as fixture;

Future<void> openAction(WidgetTester tester, String action) async {
  final target = find.byKey(Key('workshop_booking_${action}_${fixture.bookingId}'));
  await tester.scrollUntilVisible(target, 150,
    scrollable: find.byType(Scrollable).first);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppLocale.language.value = 'en');
  for (final locale in supportedLanguages) {
    for (final action in ['accept', 'decline', 'cancel']) {
      testWidgets('localized workshop $action requires consent at 320px in $locale', (tester) async {
        AppLocale.language.value = locale;
        var status = action == 'cancel' ? GarageBookingStatus.cancellationRequested
          : GarageBookingStatus.requested;
        var responses = 0;
        var cancellations = 0;
        var loads = 0;
        await fixture.render(tester, GarageBookingWorkshopScreen(
          loadInbox: () async { loads++; return [fixture.workshopRequest(status: status)]; },
          respond: (id, accept) async {
            expect(id, fixture.bookingId);
            expect(accept, action == 'accept');
            responses++;
            return status = accept ? GarageBookingStatus.confirmed : GarageBookingStatus.declined;
          },
          confirmCancellation: (id) async {
            expect(id, fixture.bookingId);
            cancellations++;
            status = GarageBookingStatus.cancelled;
          }), width: 320);
        expect(find.text(GarageUiText.get('inboxTitle')), findsOneWidget);
        expect(find.text(GarageUiText.get('inboxDisclaimer')), findsOneWidget);
        expect(find.byTooltip(GarageUiText.get('refresh')), findsOneWidget);
        await openAction(tester, action);
        expect(find.text(GarageUiText.get(action == 'accept' ? 'inboxAcceptQuestion'
          : action == 'decline' ? 'inboxDeclineQuestion' : 'inboxCancelQuestion')), findsOneWidget);
        await tester.tap(find.text(GarageUiText.get('inboxBack')));
        await tester.pumpAndSettle();
        expect(responses + cancellations, 0);
        await openAction(tester, action);
        await tester.tap(find.byKey(const Key('workshop_booking_confirm')));
        await tester.pumpAndSettle();
        expect(responses, action == 'cancel' ? 0 : 1);
        expect(cancellations, action == 'cancel' ? 1 : 0);
        expect(loads, 2);
        expect(find.byKey(Key('workshop_booking_${action}_${fixture.bookingId}')), findsNothing);
        expect(find.byKey(const Key('workshop_booking_error')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('uncertain workshop response reloads authoritative status in $locale', (tester) async {
      AppLocale.language.value = locale;
      var loads = 0;
      var calls = 0;
      await fixture.render(tester, GarageBookingWorkshopScreen(
        loadInbox: () async {
          loads++;
          return [fixture.workshopRequest(status: loads == 1
            ? GarageBookingStatus.requested : GarageBookingStatus.confirmed)];
        },
        respond: (_, __) async { calls++; throw TimeoutException('Synthetic uncertainty'); },
        confirmCancellation: (_) async => fail('Wrong operation')), width: 320);
      await openAction(tester, 'accept');
      await tester.tap(find.byKey(const Key('workshop_booking_confirm')));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(calls, 1);
      expect(tester.widget<Text>(find.byKey(const Key('workshop_booking_error'))).data,
        GarageUiText.get('inboxUncertain'));
      expect(find.byKey(Key('workshop_booking_accept_${fixture.bookingId}')), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('failed private workshop inbox never claims no requests in $locale', (tester) async {
      AppLocale.language.value = locale;
      await fixture.render(tester, GarageBookingWorkshopScreen(
        loadInbox: () async => throw StateError('Synthetic access denial'),
        respond: (_, __) async => fail('No action after denied load'),
        confirmCancellation: (_) async => fail('No action after denied load')), width: 320);
      expect(tester.widget<Text>(find.byKey(const Key('workshop_booking_error'))).data,
        GarageUiText.get('inboxLoadFailed'));
      expect(find.byKey(const Key('workshop_booking_empty')), findsNothing);
      expect(find.byKey(Key('workshop_booking_item_${fixture.bookingId}')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
