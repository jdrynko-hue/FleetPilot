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
}
