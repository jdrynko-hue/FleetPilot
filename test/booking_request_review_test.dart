import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_request_review.dart';
import 'package:fleetpilot/garage/booking_time_text.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'garage_booking_screens_test.dart' as fixture;
import 'garage_booking_request_locales_test.dart' as fields;

void main() {
  tearDown(() => AppLocale.language.value = 'en');
  for (final language in supportedLanguages) {
    testWidgets('preferred request summary fits 320px in $language', (tester) async {
      AppLocale.language.value = language;
      final when = DateTime.utc(2026, 11, 20, 10);
      await fixture.render(tester, Scaffold(body: ListView(children: [
        BookingRequestReview(service: 'brakes', when: when, workshopZone: 'Europe/Warsaw'),
      ])), width: 320);
      expect(find.textContaining(bookingLocalTimeLabel(when)), findsOneWidget);
      expect(find.text(GarageUiText.format('bookingWorkshopZone', {'zone': 'Europe/Warsaw'})), findsOneWidget);
      expect(find.text(GarageUiText.get('bookingRequestDisclaimer')), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('request review disappears after cancelled replacement time', (tester) async {
    var picks = 0;
    var writes = 0;
    final when = DateTime.now().add(const Duration(days: 2));
    await fixture.render(tester, GarageBookingRequestScreen(shop: fixture.shop,
      pickTime: (_) async => ++picks == 1 ? when : null,
      submit: ({required workspaceId, required customerName, required vehicleMake,
        required vehicleModel, required service, required concern, required desiredStart,
        required requestKey, registration}) async { writes++; return fixture.bookingId; }));
    expect(find.byType(BookingRequestReview), findsNothing);
    await fields.completeRequest(tester);
    await fields.reveal(tester, 'booking_request_review');
    expect(find.byType(BookingRequestReview), findsOneWidget);
    expect(tester.widget<BookingRequestReview>(find.byType(BookingRequestReview)).when, when);
    await fields.tap(tester, 'booking_pick_time');
    expect(find.byType(BookingRequestReview), findsNothing);
    expect(find.text(GarageUiText.get('bookingPickTime')), findsOneWidget);
    expect(writes, 0);
  });
  testWidgets('in-flight and uncertain request keep customer fields and service locked', (tester) async {
    final pending = Completer<String>();
    var writes = 0;
    await fixture.render(tester, GarageBookingRequestScreen(shop: fixture.shop,
      pickTime: (_) async => DateTime.now().add(const Duration(days: 2)),
      submit: ({required workspaceId, required customerName, required vehicleMake,
        required vehicleModel, required service, required concern, required desiredStart,
        required requestKey, registration}) { writes++; return pending.future; }));
    await fields.completeRequest(tester);
    await fields.reveal(tester, 'booking_service');
    final staleSelect = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('booking_service'))).onChanged!;
    await fields.tap(tester, 'booking_send');
    for (final uncertain in [false, true]) {
      if (uncertain) {
        pending.completeError(TimeoutException('synthetic timeout'));
        await tester.pumpAndSettle();
      }
      await fields.reveal(tester, 'booking_name');
      expect(tester.widget<TextFormField>(find.byKey(const Key('booking_name'))).enabled, isFalse);
      await fields.reveal(tester, 'booking_service');
      expect(tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('booking_service'))).onChanged, isNull);
      staleSelect('diagnostics');
      await tester.pumpAndSettle();
      await fields.reveal(tester, 'booking_request_review');
      expect(tester.widget<BookingRequestReview>(find.byType(BookingRequestReview)).service, 'brakes');
      expect(writes, 1);
    }
    expect(tester.takeException(), isNull);
  });
}
