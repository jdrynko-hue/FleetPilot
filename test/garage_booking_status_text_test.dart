import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_management_screens.dart';
import 'package:fleetpilot/garage/booking_status_text.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'garage_booking_screens_test.dart' as fixture;

void main() {
  tearDown(() => AppLocale.language.value = 'en');

  test('all six booking states stay distinct in every supported language', () {
    for (final language in supportedLanguages) {
      final labels = GarageBookingStatus.values.map(
        (status) => bookingStatusLabel(status, language: language),
      ).toList();
      expect(labels.toSet(), hasLength(GarageBookingStatus.values.length),
        reason: language);
      for (var i = 0; i < labels.length; i++) {
        expect(labels[i].trim(), isNotEmpty, reason: language);
        expect(labels[i], isNot(GarageBookingStatus.values[i].name),
          reason: '$language ${GarageBookingStatus.values[i]}');
        expect(labels[i], isNot(startsWith('booking')), reason: language);
      }
    }
    expect(bookingStatusLabel(GarageBookingStatus.requested, language: 'pl'),
      'Prośba wysłana');
    expect(bookingStatusLabel(GarageBookingStatus.cancellationRequested,
      language: 'de'), 'Stornierung ausstehend');
    expect(bookingStatusLabel(GarageBookingStatus.withdrawn, language: 'uk'),
      'Відкликано');
    expect(bookingStatusLabel(GarageBookingStatus.requested, language: 'unknown'),
      'Requested');
  });

  for (final language in supportedLanguages) {
    testWidgets('$language customer and workshop show the same readable status',
      (tester) async {
      AppLocale.language.value = language;
      const status = GarageBookingStatus.cancellationRequested;
      final expected = bookingStatusLabel(status, language: language);
      await fixture.render(tester, GarageBookingWorkshopScreen(
        loadInbox: () async => [fixture.workshopRequest(status: status)],
        respond: (id, accept) async => GarageBookingStatus.confirmed,
        confirmCancellation: (id) async {},
      ));
      expect(tester.widget<Text>(find.byKey(Key(
        'workshop_booking_status_' + fixture.bookingId))).data, expected);
      await tester.pumpWidget(MaterialApp(home: GarageMyBookingsScreen(
        loadBookings: () async => [fixture.myRequest(status: status)],
        cancel: (id) async => GarageBookingStatus.cancellationRequested,
      )));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(Key(
        'customer_booking_status_' + fixture.bookingId))).data, expected);
      expect(find.text('cancellationRequested'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
