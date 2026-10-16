import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_status_text.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'garage_booking_screens_test.dart' as fixture;

Future<void> tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> completeRequest(WidgetTester tester) async {
  for (final entry in {'booking_name':'Private Person','booking_make':'Ford',
      'booking_model':'Focus','booking_concern':'Noisy brakes'}.entries) {
    await tester.ensureVisible(find.byKey(Key(entry.key)));
    await tester.enterText(find.byKey(Key(entry.key)), entry.value);
  }
  await tap(tester, 'booking_service');
  await tester.tap(find.text(bookingServiceLabel('brakes')).last);
  await tester.pumpAndSettle();
  await tap(tester, 'booking_pick_time');
}

void main() {
  tearDown(() => AppLocale.language.value = 'en');

  for (final locale in supportedLanguages) {
    testWidgets('localized validation and single successful request at 320px in $locale', (tester) async {
      AppLocale.language.value = locale;
      final pending = Completer<String>();
      var calls = 0;
      await fixture.render(tester, GarageBookingRequestScreen(
        shop: fixture.shop,
        pickTime: (_) async => DateTime.now().add(const Duration(days: 2)),
        submit: ({required workspaceId, required customerName, required vehicleMake,
          required vehicleModel, required service, required concern,
          required desiredStart, required requestKey, registration}) async {
          calls++;
          expect(workspaceId, fixture.shop.workspaceId);
          expect(service, 'brakes');
          expect(customerName, 'Private Person');
          expect(requestKey, matches(RegExp(r'^[0-9a-f-]{36}$')));
          return pending.future;
        }), width: 320);
      expect(find.text(GarageUiText.get('bookingRequestDisclaimer')), findsOneWidget);
      final zone = tester.widget<Text>(find.byKey(const Key('booking_time_zone_hint'))).data!;
      expect(zone, contains(fixture.shop.timeZone));
      expect(zone, isNot(contains('{deviceZone}')));
      expect(zone, isNot(contains('{workshopZone}')));
      await tap(tester, 'booking_send');
      expect(calls, 0);
      await tester.ensureVisible(find.byKey(const Key('booking_name')));
      await tester.pumpAndSettle();
      expect(find.text(GarageUiText.get('bookingInvalidField')), findsWidgets);
      await completeRequest(tester);
      await tap(tester, 'booking_send');
      expect(calls, 1);
      expect(find.text(GarageUiText.get('bookingSending')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('booking_send'))).onPressed, isNull);
      pending.complete(fixture.bookingId);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('booking_sent_notice'))).data,
        GarageUiText.get('bookingRequestSent'));
      expect(find.text(GarageUiText.get('bookingDone')), findsOneWidget);
      expect(find.byKey(const Key('booking_send')), findsNothing);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('localized uncertain outcome keeps retries blocked in $locale', (tester) async {
      AppLocale.language.value = locale;
      var calls = 0;
      await fixture.render(tester, GarageBookingRequestScreen(
        shop: fixture.shop,
        pickTime: (_) async => DateTime.now().add(const Duration(days: 2)),
        submit: ({required workspaceId, required customerName, required vehicleMake,
          required vehicleModel, required service, required concern,
          required desiredStart, required requestKey, registration}) async {
          calls++;
          throw TimeoutException('Synthetic uncertain response');
        }), width: 320);
      await completeRequest(tester);
      await tap(tester, 'booking_send');
      expect(tester.widget<Text>(find.byKey(const Key('booking_request_error'))).data,
        GarageUiText.get('bookingRequestUncertain'));
      await tester.ensureVisible(find.byKey(const Key('booking_send')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const Key('booking_send'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('booking_send')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byKey(const Key('booking_sent_notice')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
