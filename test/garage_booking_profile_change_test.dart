import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';

import 'garage_booking_screens_test.dart' as fixture;
import 'garage_booking_request_locales_test.dart' as fields;

GarageBookingWorkshop profile({List<String> services = const ['brakes', 'diagnostics'],
    String zone = 'Europe/London'}) => GarageBookingWorkshop(
  workspaceId: fixture.shop.workspaceId, name: fixture.shop.name,
  city: fixture.shop.city, country: fixture.shop.country,
  timeZone: zone, services: services,
);

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  testWidgets('removed service resets selection and rejects stale menu callback', (tester) async {
    final writtenServices = <String>[];
    final BookingSubmit submit = ({required workspaceId, required customerName,
      required vehicleMake, required vehicleModel, required service,
      required concern, required desiredStart, required requestKey, registration}) async {
      writtenServices.add(service); return fixture.bookingId;
    };
    final BookingTimePicker picker = (_) async => DateTime.now().add(const Duration(days: 2));
    Future<void> mount(GarageBookingWorkshop shop) => fixture.render(tester,
      GarageBookingRequestScreen(shop: shop, submit: submit, pickTime: picker));
    await mount(profile());
    await fields.completeRequest(tester);
    final oldSelect = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('booking_service'))).onChanged!;
    await mount(profile(services: const ['diagnostics']));
    expect(tester.widget<TextFormField>(find.byKey(const Key('booking_name'))).controller!.text,
      'Private Person');
    expect(tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('booking_service'))).initialValue, isNull);
    expect(find.text(GarageUiText.get('bookingPickTime')), findsOneWidget);
    oldSelect('brakes');
    await tester.pumpAndSettle();
    final select = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('booking_service'))).onChanged!;
    select('diagnostics');
    await tester.pumpAndSettle();
    await fields.tap(tester, 'booking_pick_time');
    await fields.tap(tester, 'booking_send');
    expect(writtenServices, ['diagnostics']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timezone replacement invalidates a pending date selection', (tester) async {
    final old = Completer<DateTime?>();
    final current = Completer<DateTime?>();
    var picks = 0;
    final BookingTimePicker picker = (_) => ++picks == 1 ? old.future : current.future;
    final BookingSubmit submit = ({required workspaceId, required customerName,
      required vehicleMake, required vehicleModel, required service,
      required concern, required desiredStart, required requestKey, registration}) async => fixture.bookingId;
    Future<void> mount(String zone) => fixture.render(tester,
      GarageBookingRequestScreen(shop: profile(zone: zone), submit: submit, pickTime: picker));
    await mount('Europe/London');
    await fields.tap(tester, 'booking_pick_time');
    await mount('Europe/Paris');
    await fields.tap(tester, 'booking_pick_time');
    old.complete(DateTime.now().add(const Duration(days: 3)));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('booking_pick_time'))).onPressed, isNull);
    current.complete(DateTime.now().add(const Duration(days: 2)));
    await tester.pumpAndSettle();
    expect(picks, 2);
    expect(tester.widget<Text>(find.byKey(const Key('booking_time_zone_hint'))).data,
      contains('Europe/Paris'));
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets('profile changes preserve submission guard outcome error=$fails', (tester) async {
      final pending = Completer<String>();
      final keys = <String>[];
      final BookingSubmit submit = ({required workspaceId, required customerName,
        required vehicleMake, required vehicleModel, required service,
        required concern, required desiredStart, required requestKey, registration}) {
        keys.add(requestKey); return pending.future;
      };
      final BookingTimePicker picker = (_) async => DateTime.now().add(const Duration(days: 2));
      Future<void> mount(String zone) => fixture.render(tester,
        GarageBookingRequestScreen(shop: profile(zone: zone), submit: submit, pickTime: picker));
      await mount('Europe/London');
      await fields.completeRequest(tester);
      final oldSend = tester.widget<FilledButton>(find.byKey(const Key('booking_send'))).onPressed!;
      oldSend();
      await tester.pumpAndSettle();
      await mount('Europe/Paris');
      expect(tester.widget<FilledButton>(find.byKey(const Key('booking_send'))).onPressed, isNull);
      if (fails) { pending.completeError(TimeoutException('Private uncertain result')); }
      else { pending.complete(fixture.bookingId); }
      await tester.pumpAndSettle();
      await mount('Europe/Berlin');
      oldSend();
      await tester.pumpAndSettle();
      expect(keys, hasLength(1));
      if (fails) {
        await fields.reveal(tester, 'booking_send');
        expect(tester.widget<FilledButton>(find.byKey(const Key('booking_send'))).onPressed, isNull);
        expect(tester.widget<OutlinedButton>(find.byKey(const Key('booking_pick_time'))).onPressed, isNull);
        expect(find.textContaining('Private uncertain result'), findsNothing);
        expect(find.byKey(const Key('booking_request_error')), findsOneWidget);
      } else {
        expect(find.byKey(const Key('booking_sent_notice')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('equivalent public profile keeps the current draft', (tester) async {
    final BookingTimePicker picker = (_) async => DateTime.now().add(const Duration(days: 2));
    final services = <String>[];
    final BookingSubmit submit = ({required workspaceId, required customerName,
      required vehicleMake, required vehicleModel, required service,
      required concern, required desiredStart, required requestKey, registration}) async {
      services.add(service); return fixture.bookingId;
    };
    Future<void> mount() => fixture.render(tester,
      GarageBookingRequestScreen(shop: profile(services: ['brakes', 'diagnostics']),
        submit: submit, pickTime: picker));
    await mount();
    await fields.completeRequest(tester);
    await mount();
    await fields.tap(tester, 'booking_send');
    expect(services, ['brakes']);
    expect(tester.takeException(), isNull);
  });
}
