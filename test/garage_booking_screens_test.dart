import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';
import 'package:fleetpilot/garage/booking_management_screens.dart';

const shop = GarageBookingWorkshop(
  workspaceId: '00000000-0000-4000-8000-000000000101',
  name: 'Independent Garage',
  city: 'Dunstable',
  country: 'GB',
  timeZone: 'Europe/London',
  services: ['brakes','diagnostics'],
);
const bookingId = '00000000-0000-4000-8000-000000000201';

GarageBookingInboxItem workshopRequest({
  GarageBookingStatus status = GarageBookingStatus.requested,
}) => GarageBookingInboxItem(
  id: bookingId, customerName: 'Private Person',
  customerEmail: 'private@example.test',
  vehicleMake: 'Ford', vehicleModel: 'Focus',
  service: 'brakes', concern: 'Noisy front brakes',
  startAt: DateTime.utc(2026,11,20,10), durationMinutes:60,
  status: status);

GarageBookingSummary myRequest({
  GarageBookingStatus status = GarageBookingStatus.requested,
}) => GarageBookingSummary(
  id:bookingId, workspaceId:shop.workspaceId,
  workshopName:shop.name, startAt:DateTime.utc(2026,11,20,10),
  service:'brakes',status:status);

Future<void> render(WidgetTester tester, Widget screen,
    {double width = 375}) async {
  tester.view.physicalSize = Size(width, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppLocale.language.value='en');
  tearDown(() => AppLocale.language.value='en');

  for (final width in [320.0,375.0,390.0,900.0]) {
    testWidgets('mobile/desktop directory never promises availability at $width',
      (tester) async {
      await render(tester, GarageBookingSearchScreen(
        search: ({city}) async => [shop],
        submit: ({
          required workspaceId,required customerName,
          required vehicleMake,required vehicleModel,
          required service,required concern,required desiredStart,
          registration,
        }) async => bookingId,
      ),width:width);
      expect(find.byKey(const Key('booking_not_guaranteed')),findsOneWidget);
      await tester.tap(find.byKey(const Key('booking_search_submit')));
      await tester.pumpAndSettle();
      expect(find.text(shop.name),findsOneWidget);
      expect(find.byKey(Key('booking_open_' + shop.workspaceId)),
        findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }

  testWidgets('service filter narrows city results without implying free slots',
      (tester) async {
    var searches = 0;
    await render(tester, GarageBookingSearchScreen(
      search: ({city}) async { searches++; return [shop]; },
      submit: ({
        required workspaceId, required customerName,
        required vehicleMake, required vehicleModel, required service,
        required concern, required desiredStart, registration,
      }) async => bookingId,
    ), width: 320);
    await tester.tap(find.byKey(const Key('booking_search_submit')));
    await tester.pumpAndSettle();
    expect(searches, 1);
    expect(find.byKey(Key('booking_open_' + shop.workspaceId)), findsOneWidget);

    await tester.tap(find.byKey(const Key('booking_search_service')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tyres').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking_search_no_service')), findsOneWidget);
    expect(find.byKey(Key('booking_open_' + shop.workspaceId)), findsNothing);
    expect(searches, 1); // Filtering must not fabricate API results.

    await tester.tap(find.byKey(const Key('booking_search_service')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brakes').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking_open_' + shop.workspaceId)), findsOneWidget);
    expect(find.byKey(const Key('booking_search_count')), findsOneWidget);
    expect(find.byKey(const Key('booking_not_guaranteed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search failure purges previously listed shops', (tester) async {
    var fail=false;
    await render(tester,GarageBookingSearchScreen(
      search: ({city}) async {
        if (fail) throw StateError('Permission removed');
        return [shop];
      },
      submit: ({
          required workspaceId,required customerName,
          required vehicleMake,required vehicleModel,
          required service,required concern,required desiredStart,
          registration,
      }) async => bookingId,
    ));
    await tester.tap(find.byKey(const Key('booking_search_submit')));
    await tester.pumpAndSettle();
    expect(find.text(shop.name),findsOneWidget);
    fail=true;
    await tester.tap(find.byKey(const Key('booking_search_submit')));
    await tester.pumpAndSettle();
    expect(find.text(shop.name),findsNothing);
    expect(find.byKey(const Key('booking_search_error')),findsOneWidget);
  });

  testWidgets('customer submits a request once; never gets instant confirmation',
      (tester) async {
    var count=0;
    await render(tester,GarageBookingRequestScreen(
      shop:shop,
      pickTime:(context) async => DateTime.now().add(const Duration(days:2)),
      submit: ({
        required workspaceId, required customerName,
        required vehicleMake, required vehicleModel,
        required service, required concern, required desiredStart,
        registration,
      }) async {
        count++;
        expect(workspaceId,shop.workspaceId);
        expect(customerName,'Private Person');
        expect(vehicleMake,'Ford');
        expect(vehicleModel,'Focus');
        expect(service,'brakes');
        expect(concern,'Noisy front brakes');
        expect(registration,isNull);
        return bookingId;
      },
    ));
    await tester.enterText(find.byKey(const Key('booking_name')),'Private Person');
    await tester.enterText(find.byKey(const Key('booking_make')),'Ford');
    await tester.enterText(find.byKey(const Key('booking_model')),'Focus');
    await tester.tap(find.byKey(const Key('booking_service')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('brakes').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('booking_concern')),
        'Noisy front brakes');
    await tester.ensureVisible(find.byKey(const Key('booking_pick_time')));
    await tester.tap(find.byKey(const Key('booking_pick_time')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('booking_send')));
    await tester.tap(find.byKey(const Key('booking_send')));
    await tester.pumpAndSettle();
    expect(count,1);
    expect(find.byKey(const Key('booking_sent_notice')),findsOneWidget);
    expect(find.textContaining('NOT confirmed'),findsOneWidget);
    expect(find.byKey(const Key('booking_send')),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('workshop must explicitly confirm; then re-fetches status',
    (tester) async {
    var confirmationCount=0;
    var loads=0;
    await render(tester,GarageBookingWorkshopScreen(
      loadInbox:() async {
        loads++;
        return [workshopRequest(status:confirmationCount==0
          ? GarageBookingStatus.requested : GarageBookingStatus.confirmed)];
      },
      respond:(id,accept) async {
        expect(id,bookingId);
        expect(accept,true);
        confirmationCount++;
        return GarageBookingStatus.confirmed;
      },
      confirmCancellation:(id) async {},
    ));
    expect(find.text('Private Person'),findsOneWidget);
    await tester.tap(find.byKey(Key('workshop_booking_accept_'+bookingId)));
    await tester.pumpAndSettle();
    expect(confirmationCount,0);
    await tester.tap(find.byKey(const Key('workshop_booking_confirm')));
    await tester.pumpAndSettle();
    expect(confirmationCount,1);
    expect(loads,2);
    expect(find.byKey(Key('workshop_booking_accept_'+bookingId)),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('revoked workshop access hides customer email immediately',
    (tester) async {
    var denied=false;
    await render(tester,GarageBookingWorkshopScreen(
      loadInbox: () async {
        if (denied) throw StateError('RLS revoked');
        return [workshopRequest()];
      },
      respond:(id,accept) async => GarageBookingStatus.confirmed,
      confirmCancellation:(id) async {},
    ));
    expect(find.text('private@example.test'),findsOneWidget);
    denied=true;
    await tester.tap(find.byKey(const Key('workshop_booking_refresh')));
    await tester.pumpAndSettle();
    expect(find.text('private@example.test'),findsNothing);
    expect(find.byKey(const Key('workshop_booking_error')),findsOneWidget);
  });

  testWidgets('customer sees requested not confirmed and needs confirmation to cancel',
    (tester) async {
    var cancelled=false;
    await render(tester,GarageMyBookingsScreen(
      loadBookings: () async => [myRequest(status:cancelled
        ? GarageBookingStatus.withdrawn : GarageBookingStatus.requested)],
      cancel:(id) async {
        expect(id,bookingId);
        cancelled=true;
        return GarageBookingStatus.withdrawn;
      },
    ));
    expect(find.text('Requested'),findsOneWidget);
    await tester.tap(find.byKey(Key('customer_booking_cancel_'+bookingId)));
    await tester.pumpAndSettle();
    expect(cancelled,false);
    await tester.tap(find.byKey(const Key('customer_booking_confirm_cancel')));
    await tester.pumpAndSettle();
    expect(cancelled,true);
    expect(find.text('Withdrawn'),findsOneWidget);
    expect(find.byKey(Key('customer_booking_cancel_'+bookingId)),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
