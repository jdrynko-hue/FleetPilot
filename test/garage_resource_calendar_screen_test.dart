import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/resource_calendar_repository.dart';
import 'package:fleetpilot/garage/resource_calendar_screen.dart';

const bay1='00000000-0000-4000-8000-000000000101';
const bay2='00000000-0000-4000-8000-000000000102';
const requestId='00000000-0000-4000-8000-000000000103';
const noticeId='00000000-0000-4000-8000-000000000104';

final resources = [
  const GarageCalendarResource(id:bay1,name:'Bay One',active:true),
  const GarageCalendarResource(id:bay2,name:'Bay Two',active:true),
];

GarageBookingInboxItem req() => GarageBookingInboxItem(
  id:requestId,customerName:'Booking Person',customerEmail:'private@example.test',
  vehicleMake:'Ford',vehicleModel:'Focus',service:'brakes',
  concern:'Noisy brakes',startAt:DateTime.utc(2026,11,20,10),
  durationMinutes:60,status:GarageBookingStatus.requested,
);

GarageCalendarAppointment appointment() => GarageCalendarAppointment(
  bookingId:requestId,resourceId:bay2,resourceName:'Bay Two',
  startAt:DateTime.utc(2026,11,20,10),durationMinutes:60,
  status:'confirmed',customerName:'Booking Person',
);

GarageBookingNotice notification() => GarageBookingNotice(
  id:noticeId,bookingId:requestId,event:'confirmed',
  occurredAt:DateTime.utc(2026,11,20,10),
);

Future<void> mount(WidgetTester tester,Widget child,{double width=375}) async {
 tester.view.physicalSize=Size(width,850);
 tester.view.devicePixelRatio=1;
 addTearDown(tester.view.resetPhysicalSize);
 addTearDown(tester.view.resetDevicePixelRatio);
 await tester.pumpWidget(MaterialApp(home:child));
 await tester.pumpAndSettle();
}

void main(){
 setUp(()=>AppLocale.language.value='en');
 tearDown(()=>AppLocale.language.value='en');

 for(final width in [320.0,375.0,390.0,900.0]){
  testWidgets('calendar requires explicit resource selection at $width',
    (tester) async {
    await mount(tester,GarageResourceCalendarScreen(
      loadResources:() async => resources,
      loadRequests:() async => [req()],
      loadCalendar:() async => [],
      confirmSlot:(booking,resource) async => 'confirmed',
    ),width:width);
    expect(find.text('Booking Person'),findsOneWidget);
    final btn=tester.widget<FilledButton>(
      find.byKey(Key('garage_calendar_accept_'+requestId)));
    expect(btn.onPressed,isNull);
    expect(tester.takeException(),isNull);
  });
 }

 testWidgets('pending and confirmed calendar entries include appointment zone', (tester) async {
  await mount(tester, GarageResourceCalendarScreen(
   loadResources: () async => resources, loadRequests: () async => [req()],
   loadCalendar: () async => [appointment()],
   confirmSlot: (booking, resource) async => 'confirmed',
  ));
  final local = DateTime.utc(2026, 11, 20, 10).toLocal();
  final expected = '${local.toString().substring(0, 16)} (${local.timeZoneName})';
  expect(find.descendant(of: find.byKey(Key('garage_calendar_pending_' + requestId)),
    matching: find.text(expected)), findsOneWidget);
  final confirmed = find.byKey(Key('garage_calendar_appointment_' + requestId));
  await tester.scrollUntilVisible(confirmed, 300);
  await tester.pumpAndSettle();
  expect(find.descendant(of: confirmed,
    matching: find.textContaining(expected)), findsOneWidget);
  expect(tester.takeException(), isNull);
 });

 testWidgets('selecting Bay Two and confirming calls exact resource RPC once',
   (tester) async {
   var calls=0;
   var confirmed=false;
   await mount(tester,GarageResourceCalendarScreen(
     loadResources:() async => resources,
     loadRequests:() async => confirmed ? [] : [req()],
     loadCalendar:() async => confirmed ? [appointment()] : [],
     confirmSlot:(booking,resource) async {
       calls++;
       expect(booking,requestId);
       expect(resource,bay2);
       confirmed=true;
       return 'confirmed';
     },
   ));
   await tester.ensureVisible(find.byKey(Key('garage_calendar_select_'+requestId)));
   await tester.tap(find.byKey(Key('garage_calendar_select_'+requestId)));
   await tester.pumpAndSettle();
   await tester.tap(find.text('Bay Two').last);
   await tester.pumpAndSettle();
   await tester.ensureVisible(find.byKey(Key('garage_calendar_accept_'+requestId)));
   await tester.tap(find.byKey(Key('garage_calendar_accept_'+requestId)));
   await tester.pumpAndSettle();
   expect(calls,0);
   await tester.tap(find.byKey(const Key('calendar_confirm_action')));
   await tester.pumpAndSettle();
   expect(calls,1);
   expect(find.byKey(Key('garage_calendar_pending_'+requestId)),findsNothing);
   expect(find.byKey(Key('garage_calendar_appointment_'+requestId)),findsOneWidget);
   expect(tester.takeException(),isNull);
 });

 testWidgets('permission revocation purges private calendar and inbox',
   (tester) async {
   var revoke=false;
   await mount(tester,GarageResourceCalendarScreen(
     loadResources:() async {
       if (revoke) throw StateError('Forbidden');
       return resources;
     },
     loadRequests:() async => [req()],
     loadCalendar:() async => [],
     confirmSlot:(booking,resource) async => 'confirmed',
   ));
   expect(find.text('Booking Person'),findsOneWidget);
   revoke=true;
   await tester.tap(find.byKey(const Key('garage_calendar_refresh')));
   await tester.pumpAndSettle();
   expect(find.text('Booking Person'),findsNothing);
   expect(find.byKey(const Key('garage_calendar_error')),findsOneWidget);
 });

 testWidgets('notification screen only marks user-scoped alert as read',
   (tester) async {
   var acknowledgements=0;
   var read=false;
   await mount(tester,GarageBookingNotificationsScreen(
     load:() async => [
       GarageBookingNotice(
         id:noticeId,bookingId:requestId,event:'confirmed',
         occurredAt:DateTime.utc(2026,11,20,10),
         readAt:read ? DateTime.utc(2026,11,20,11) : null),
     ],
     acknowledge:(id) async {
       expect(id,noticeId);
       acknowledgements++;
       read=true;
       return true;
     },
   ));
   expect(find.byKey(Key('garage_notification_mark_'+noticeId)),findsOneWidget);
   await tester.tap(find.byKey(Key('garage_notification_mark_'+noticeId)));
   await tester.pumpAndSettle();
   expect(acknowledgements,1);
   expect(find.byKey(Key('garage_notification_mark_'+noticeId)),findsNothing);
 });

 testWidgets('notification load failure hides earlier private event data',
   (tester) async {
   var fail=false;
   await mount(tester,GarageBookingNotificationsScreen(
     load:() async {
       if(fail)throw StateError('Revoked');
       return [notification()];
     },
     acknowledge:(id) async => true,
   ));
   expect(find.text('confirmed'),findsOneWidget);
   fail=true;
   await tester.tap(find.byKey(const Key('garage_notifications_refresh')));
   await tester.pumpAndSettle();
   expect(find.text('confirmed'),findsNothing);
   expect(find.byKey(const Key('garage_notifications_error')),findsOneWidget);
 });

 for (final stage in ['resources', 'requests', 'calendar']) {
  testWidgets('calendar discards old scope during $stage load', (tester) async {
   final barrier = Completer<void>();
   final calls = <String>[];
   Future<T> old<T>(String name, T value) async {
    calls.add(name);
    if (name == stage) await barrier.future;
    return value;
   }
   await tester.pumpWidget(MaterialApp(home: GarageResourceCalendarScreen(
    loadResources: () => old('resources', resources),
    loadRequests: () => old('requests', [req()]),
    loadCalendar: () => old('calendar', [appointment()]),
    confirmSlot: (booking, resource) async => 'confirmed',
   )));
   await tester.pump();
   expect(calls.last, stage);
   await tester.pumpWidget(MaterialApp(home: GarageResourceCalendarScreen(
    loadResources: () async => [], loadRequests: () async => [],
    loadCalendar: () async => [], confirmSlot: (booking, resource) async => 'confirmed',
   )));
   await tester.pumpAndSettle();
   final oldCalls = calls.length;
   barrier.complete();
   await tester.pumpAndSettle();
   expect(calls.length, oldCalls);
   expect(find.text('private@example.test'), findsNothing);
   expect(find.text('Booking Person'), findsNothing);
   expect(find.text('Bay One'), findsNothing);
   expect(find.byKey(const Key('garage_calendar_error')), findsNothing);
   expect(tester.takeException(), isNull);
  });
 }

 Future<void> openConfirmation(WidgetTester tester) async {
  final selector = find.byKey(Key('garage_calendar_select_' + requestId));
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bay Two').last);
  await tester.pumpAndSettle();
  final accept = find.byKey(Key('garage_calendar_accept_' + requestId));
  await tester.ensureVisible(accept);
  await tester.pumpAndSettle();
  await tester.tap(accept);
  await tester.pumpAndSettle();
 }

 testWidgets('calendar dialog cannot confirm under replacement scope', (tester) async {
  var oldCalls = 0;
  var newCalls = 0;
  await mount(tester, GarageResourceCalendarScreen(
   loadResources: () async => resources, loadRequests: () async => [req()],
   loadCalendar: () async => [],
   confirmSlot: (booking, resource) async { oldCalls++; return 'confirmed'; },
  ));
  await openConfirmation(tester);
  await tester.pumpWidget(MaterialApp(home: GarageResourceCalendarScreen(
   loadResources: () async => resources, loadRequests: () async => [req()],
   loadCalendar: () async => [],
   confirmSlot: (booking, resource) async { newCalls++; return 'confirmed'; },
  )));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('calendar_confirm_action')));
  await tester.pumpAndSettle();
  expect(oldCalls, 0);
  expect(newCalls, 0);
  expect(tester.widget<FilledButton>(find.byKey(
    Key('garage_calendar_accept_' + requestId))).onPressed, isNull);
  expect(tester.takeException(), isNull);
 });

 for (final fails in [false, true]) {
  testWidgets('old calendar mutation cannot refresh new scope (error=$fails)', (tester) async {
   final pending = Completer<String>();
   var newLoads = 0;
   await mount(tester, GarageResourceCalendarScreen(
    loadResources: () async => resources, loadRequests: () async => [req()],
    loadCalendar: () async => [], confirmSlot: (booking, resource) => pending.future,
   ));
   await openConfirmation(tester);
   await tester.tap(find.byKey(const Key('calendar_confirm_action')));
   await tester.pump();
   await tester.pumpWidget(MaterialApp(home: GarageResourceCalendarScreen(
    loadResources: () async => [], loadRequests: () async => [],
    loadCalendar: () async { newLoads++; return []; },
    confirmSlot: (booking, resource) async => 'confirmed',
   )));
   await tester.pumpAndSettle();
   expect(newLoads, 1);
   if (fails) { pending.completeError(StateError('old private failure')); }
   else { pending.complete('confirmed'); }
   await tester.pumpAndSettle();
   expect(newLoads, 1);
   expect(find.byKey(const Key('garage_calendar_error')), findsNothing);
   expect(find.text('Booking Person'), findsNothing);
   expect(tester.takeException(), isNull);
  });
 }

 testWidgets('notifications discard an old account load', (tester) async {
  final pending = Completer<List<GarageBookingNotice>>();
  await tester.pumpWidget(MaterialApp(home: GarageBookingNotificationsScreen(
   load: () => pending.future, acknowledge: (id) async => true,
  )));
  await tester.pump();
  await tester.pumpWidget(MaterialApp(home: GarageBookingNotificationsScreen(
   load: () async => [], acknowledge: (id) async => true,
  )));
  await tester.pumpAndSettle();
  pending.complete([notification()]);
  await tester.pumpAndSettle();
  expect(find.byKey(Key('garage_notification_' + noticeId)), findsNothing);
  expect(find.byKey(const Key('garage_notifications_empty')), findsOneWidget);
  expect(tester.takeException(), isNull);
 });

 for (final fails in [false, true]) {
  testWidgets('old read acknowledgement cannot refresh new account (error=$fails)', (tester) async {
   final pending = Completer<bool>();
   var newLoads = 0;
   await mount(tester, GarageBookingNotificationsScreen(
    load: () async => [notification()], acknowledge: (id) => pending.future,
   ));
   await tester.tap(find.byKey(Key('garage_notification_mark_' + noticeId)));
   await tester.pump();
   await tester.pumpWidget(MaterialApp(home: GarageBookingNotificationsScreen(
    load: () async { newLoads++; return []; }, acknowledge: (id) async => true,
   )));
   await tester.pumpAndSettle();
   expect(newLoads, 1);
   if (fails) { pending.completeError(StateError('old private failure')); }
   else { pending.complete(true); }
   await tester.pumpAndSettle();
   expect(newLoads, 1);
   expect(find.byKey(const Key('garage_notifications_error')), findsNothing);
   expect(find.byKey(Key('garage_notification_' + noticeId)), findsNothing);
   expect(tester.takeException(), isNull);
  });
 }

}
