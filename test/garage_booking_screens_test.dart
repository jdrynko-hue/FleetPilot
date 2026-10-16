import 'dart:async';

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
          required service,required concern,required desiredStart, required requestKey,
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
          required service,required concern,required desiredStart, required requestKey,
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
        required service, required concern, required desiredStart, required requestKey,
        registration,
      }) async {
        count++;
        expect(workspaceId,shop.workspaceId);
        expect(requestKey, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
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
    await tester.tap(find.text('Brakes').last);
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

  testWidgets('search ignores stale results after changing directory scope',
      (tester) async {
    final pending = Completer<List<GarageBookingWorkshop>>();
    final BookingSubmit submit = ({
      required workspaceId, required customerName, required vehicleMake,
      required vehicleModel, required service, required concern,
      required desiredStart, required requestKey, registration,
    }) async => bookingId;
    const otherShop = GarageBookingWorkshop(
      workspaceId: '00000000-0000-4000-8000-000000000102',
      name: 'Second Workshop', city: 'Luton', country: 'GB',
      timeZone: 'Europe/London', services: ['diagnostics'],
    );
    await render(tester, GarageBookingSearchScreen(
      search: ({city}) => pending.future,
      submit: submit,
    ));
    await tester.tap(find.byKey(const Key('booking_search_submit')));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: GarageBookingSearchScreen(
      search: ({city}) async => [otherShop],
      submit: submit,
    )));
    await tester.pumpAndSettle();
    pending.complete([shop]);
    await tester.pumpAndSettle();
    expect(find.text(shop.name), findsNothing);
    await tester.tap(find.byKey(const Key('booking_search_submit')));
    await tester.pumpAndSettle();
    expect(find.text(otherShop.name), findsOneWidget);
    expect(find.text(shop.name), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking form clears customer details on workshop scope change',
      (tester) async {
    final pending = Completer<String>();
    var oldSubmissions = 0;
    var newSubmissions = 0;
    final BookingTimePicker picker = (_) async =>
        DateTime.now().add(const Duration(days: 2));
    final BookingSubmit oldSubmit = ({
      required workspaceId, required customerName, required vehicleMake,
      required vehicleModel, required service, required concern,
      required desiredStart, required requestKey, registration,
    }) {
      oldSubmissions++;
      expect(workspaceId, shop.workspaceId);
      return pending.future;
    };
    const otherShop = GarageBookingWorkshop(
      workspaceId: '00000000-0000-4000-8000-000000000102',
      name: 'Second Workshop', city: 'Luton', country: 'GB',
      timeZone: 'Europe/London', services: ['diagnostics'],
    );
    final BookingSubmit newSubmit = ({
      required workspaceId, required customerName, required vehicleMake,
      required vehicleModel, required service, required concern,
      required desiredStart, required requestKey, registration,
    }) async {
      newSubmissions++;
      expect(workspaceId, otherShop.workspaceId);
      return bookingId;
    };
    await render(tester, GarageBookingRequestScreen(
      shop: shop, submit: oldSubmit, pickTime: picker,
    ));
    await tester.enterText(find.byKey(const Key('booking_name')), 'Private Person');
    await tester.enterText(find.byKey(const Key('booking_make')), 'Ford');
    await tester.enterText(find.byKey(const Key('booking_model')), 'Focus');
    await tester.tap(find.byKey(const Key('booking_service')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brakes').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('booking_concern')), 'Noisy brakes');
    await tester.ensureVisible(find.byKey(const Key('booking_pick_time')));
    await tester.tap(find.byKey(const Key('booking_pick_time')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('booking_send')));
    await tester.tap(find.byKey(const Key('booking_send')));
    await tester.pump();
    expect(oldSubmissions, 1);
    await tester.pumpWidget(MaterialApp(home: GarageBookingRequestScreen(
      shop: otherShop, submit: newSubmit, pickTime: picker,
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(
      find.byKey(const Key('booking_name'))).controller!.text, isEmpty);
    expect(tester.widget<TextFormField>(
      find.byKey(const Key('booking_concern'))).controller!.text, isEmpty);
    expect(find.byKey(const Key('booking_sent_notice')), findsNothing);
    pending.complete(bookingId);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking_sent_notice')), findsNothing);
    expect(newSubmissions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old workshop date picker result cannot populate new booking',
      (tester) async {
    final pending = Completer<DateTime?>();
    final BookingSubmit submit = ({
      required workspaceId, required customerName, required vehicleMake,
      required vehicleModel, required service, required concern,
      required desiredStart, required requestKey, registration,
    }) async => bookingId;
    const otherShop = GarageBookingWorkshop(
      workspaceId: '00000000-0000-4000-8000-000000000102',
      name: 'Second Workshop', city: 'Luton', country: 'GB',
      timeZone: 'Europe/London', services: ['diagnostics'],
    );
    await render(tester, GarageBookingRequestScreen(
      shop: shop, submit: submit, pickTime: (_) => pending.future,
    ));
    await tester.ensureVisible(find.byKey(const Key('booking_pick_time')));
    await tester.tap(find.byKey(const Key('booking_pick_time')));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: GarageBookingRequestScreen(
      shop: otherShop, submit: submit,
      pickTime: (_) async => DateTime.now().add(const Duration(days: 3)),
    )));
    await tester.pumpAndSettle();
    pending.complete(DateTime.now().add(const Duration(days: 2)));
    await tester.pumpAndSettle();
    expect(find.text('Choose date and time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('workshop switch hides old customer email and late inbox',
      (tester) async {
    final pending = Completer<List<GarageBookingInboxItem>>();
    final oldLoad = () => pending.future;
    final newLoad = () async => <GarageBookingInboxItem>[];
    final respond = (String id, bool accept) async =>
        GarageBookingStatus.confirmed;
    final cancel = (String id) async {};
    await tester.pumpWidget(MaterialApp(home: GarageBookingWorkshopScreen(
      loadInbox: oldLoad, respond: respond, confirmCancellation: cancel,
    )));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: GarageBookingWorkshopScreen(
      loadInbox: newLoad, respond: respond, confirmCancellation: cancel,
    )));
    await tester.pumpAndSettle();
    pending.complete([workshopRequest()]);
    await tester.pumpAndSettle();
    expect(find.text('private@example.test'), findsNothing);
    expect(find.text('Private Person'), findsNothing);
    expect(find.byKey(const Key('workshop_booking_empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('private booking scope discards late old customer history',
      (tester) async {
    final pending = Completer<List<GarageBookingSummary>>();
    final oldLoad = () => pending.future;
    final newLoad = () async => <GarageBookingSummary>[];
    final cancel = (String id) async => GarageBookingStatus.withdrawn;
    await tester.pumpWidget(MaterialApp(home: GarageMyBookingsScreen(
      loadBookings: oldLoad, cancel: cancel,
    )));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: GarageMyBookingsScreen(
      loadBookings: newLoad, cancel: cancel,
    )));
    await tester.pumpAndSettle();
    pending.complete([myRequest()]);
    await tester.pumpAndSettle();
    expect(find.text(shop.name), findsNothing);
    expect(find.byKey(const Key('customer_booking_empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching workshop while confirmation open blocks old action',
      (tester) async {
    var oldCalls = 0;
    var newCalls = 0;
    final oldLoad = () async => [workshopRequest()];
    final newLoad = () async => <GarageBookingInboxItem>[];
    await tester.pumpWidget(MaterialApp(home: GarageBookingWorkshopScreen(
      loadInbox: oldLoad,
      respond: (id, accept) async {
        oldCalls++;
        return GarageBookingStatus.confirmed;
      },
      confirmCancellation: (id) async {},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('workshop_booking_accept_' + bookingId)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(home: GarageBookingWorkshopScreen(
      loadInbox: newLoad,
      respond: (id, accept) async {
        newCalls++;
        return GarageBookingStatus.confirmed;
      },
      confirmCancellation: (id) async {},
    )));
    await tester.pump();
    await tester.tap(find.byKey(const Key('workshop_booking_confirm')));
    await tester.pumpAndSettle();
    expect(oldCalls, 0);
    expect(newCalls, 0);
    expect(find.byKey(const Key('workshop_booking_empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching customer during cancellation dialog blocks old RPC',
      (tester) async {
    var oldCalls = 0;
    var newCalls = 0;
    final oldLoad = () async => [myRequest()];
    final newLoad = () async => <GarageBookingSummary>[];
    await tester.pumpWidget(MaterialApp(home: GarageMyBookingsScreen(
      loadBookings: oldLoad,
      cancel: (id) async {
        oldCalls++;
        return GarageBookingStatus.withdrawn;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('customer_booking_cancel_' + bookingId)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(home: GarageMyBookingsScreen(
      loadBookings: newLoad,
      cancel: (id) async {
        newCalls++;
        return GarageBookingStatus.withdrawn;
      },
    )));
    await tester.pump();
    await tester.tap(find.byKey(const Key('customer_booking_confirm_cancel')));
    await tester.pumpAndSettle();
    expect(oldCalls, 0);
    expect(newCalls, 0);
    expect(find.byKey(const Key('customer_booking_empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  testWidgets('uncertain booking submit prevents a duplicate request',
      (tester) async {
    var submissions = 0;
    await render(tester, GarageBookingRequestScreen(
      shop: shop,
      pickTime: (_) async => DateTime.now().add(const Duration(days: 2)),
      submit: ({
        required workspaceId, required customerName,
        required vehicleMake, required vehicleModel,
        required service, required concern, required desiredStart, required requestKey,
        registration,
      }) async {
        submissions++;
        throw StateError('private server details');
      },
    ));
    await tester.enterText(find.byKey(const Key('booking_name')), 'Private Person');
    await tester.enterText(find.byKey(const Key('booking_make')), 'Ford');
    await tester.enterText(find.byKey(const Key('booking_model')), 'Focus');
    await tester.tap(find.byKey(const Key('booking_service')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brakes').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('booking_concern')), 'Noisy brakes');
    await tester.ensureVisible(find.byKey(const Key('booking_pick_time')));
    await tester.tap(find.byKey(const Key('booking_pick_time')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('booking_send')));
    await tester.tap(find.byKey(const Key('booking_send')));
    await tester.pumpAndSettle();
    expect(submissions, 1);
    expect(find.textContaining('Request outcome is uncertain'), findsOneWidget);
    expect(find.textContaining('private server details'), findsNothing);
    expect(find.byKey(const Key('booking_sent_notice')), findsNothing);
    // The error makes the long mobile ListView taller. Scroll to the
    // disabled action before inspecting the lazily built button.
    await tester.scrollUntilVisible(
      find.byKey(const Key('booking_send')), 160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('booking_send')),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

}
