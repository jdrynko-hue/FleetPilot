import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_status_text.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';
import 'garage_booking_screens_test.dart' as fixture;

void main() {
  tearDown(() => AppLocale.language.value = 'en');
  for (final width in [320.0, 390.0]) {
    for (final sample in [('uk', 'maintenance'), ('fr', 'electrical'), ('de', 'bodywork')]) {
      testWidgets('${sample.$1} service picker fits ${width}px with 200% text',
        (tester) async {
        AppLocale.language.value = sample.$1;
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final shop = GarageBookingWorkshop(
          workspaceId: fixture.shop.workspaceId,
          name: 'Independent workshop', city: 'Dunstable', country: 'GB',
          timeZone: 'Europe/London', services: GarageBookingService.values.toList(),
        );
        var submissions = 0;
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: GarageBookingRequestScreen(shop: shop,
            submit: ({required workspaceId, required customerName,
              required vehicleMake, required vehicleModel, required service,
              required concern, required desiredStart, required requestKey,
              registration}) async {
              submissions++;
              return fixture.bookingId;
            },
          ),
        ));
        await tester.pumpAndSettle();
        final picker = find.byKey(const Key('booking_service'));
        await tester.scrollUntilVisible(picker, 200,
          scrollable: find.byType(Scrollable).first);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        final option = find.text(bookingServiceLabel(sample.$2,
          language: sample.$1)).last;
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(tester.widget<DropdownButtonFormField<String>>(picker).initialValue,
          sample.$2);
        await tester.scrollUntilVisible(find.byKey(const Key('booking_send')), 200,
          scrollable: find.byType(Scrollable).first);
        expect(find.byKey(const Key('booking_send')), findsOneWidget);
        expect(submissions, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
