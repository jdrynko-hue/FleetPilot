import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/calendar_settings_screen.dart';
import 'package:fleetpilot/garage/resource_calendar_repository.dart';

const mechanicId='00000000-0000-4000-8000-000000000003';
const bayId='00000000-0000-4000-8000-000000000101';

const member=GarageRosterMechanic(
 userId:mechanicId,email:'mechanic@example.test');

Future<void> mount(WidgetTester tester,Widget screen,
    {double width=375}) async {
 tester.view.physicalSize=Size(width,840);
 tester.view.devicePixelRatio=1;
 addTearDown(tester.view.resetPhysicalSize);
 addTearDown(tester.view.resetDevicePixelRatio);
 await tester.pumpWidget(MaterialApp(home:screen));
 await tester.pumpAndSettle();
}

Future<void> findBay(WidgetTester tester) async {
 await tester.scrollUntilVisible(
   find.byKey(const Key('garage_settings_assign_'+bayId)),
   140,scrollable:find.byType(Scrollable).first);
 await tester.drag(find.byType(ListView).first,const Offset(0,-140));
 await tester.pumpAndSettle();
}

void main(){
 setUp(()=>AppLocale.language.value='en');
 tearDown(()=>AppLocale.language.value='en');

 testWidgets('workshop owner selects own mechanic; server confirmation reloads bay',
 (tester) async {
  var assigned=false;
  var calls=0;
  await mount(tester,GarageCalendarSettingsScreen(
    loadHours:() async=>[],
    loadResources:() async=>[
      GarageCalendarResource(id:bayId,name:'Inspection Bay',
        active:true,mechanicUserId:assigned?mechanicId:null),
    ],
    setHours:(day,open,close,enabled) async=>true,
    addResource:(name) async=>bayId,
    setResourceActive:(id,active) async=>true,
    loadMechanics:() async=>[member],
    assignMechanic:(id,staff) async {
      expect(id,bayId);
      expect(staff,mechanicId);
      assigned=true;
      calls++;
      return true;
    },
  ),width:320);
  await findBay(tester);
  expect(find.text('Mechanic: unassigned'),findsOneWidget);
  await tester.tap(find.byKey(const Key('garage_settings_assign_'+bayId)));
  await tester.pumpAndSettle();
  expect(find.text('mechanic@example.test'),findsOneWidget);
  expect(calls,0);
  await tester.tap(find.byKey(const Key('garage_mechanic_pick_'+mechanicId)));
  await tester.pumpAndSettle();
  expect(calls,1);
  await findBay(tester);
  expect(find.text('mechanic@example.test'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });

 testWidgets('failed reassignment keeps old staff and shows error after refresh',
 (tester) async {
  await mount(tester,GarageCalendarSettingsScreen(
    loadHours:() async=>[],
    loadResources:() async=>[
      const GarageCalendarResource(id:bayId,name:'Inspection Bay',
        active:true,mechanicUserId:mechanicId),
    ],
    setHours:(day,open,close,enabled) async=>true,
    addResource:(name) async=>bayId,
    setResourceActive:(id,active) async=>true,
    loadMechanics:() async=>[member],
    assignMechanic:(id,staff) async {
      expect(staff,isNull);
      throw StateError('Cannot reassign occupied bay');
    },
  ));
  await findBay(tester);
  await tester.tap(find.byKey(const Key('garage_settings_assign_'+bayId)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('garage_mechanic_unassign')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('garage_settings_notice')),findsOneWidget);
  await findBay(tester);
  expect(find.text('mechanic@example.test'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });

 testWidgets('owner roster permission revoked clears emails and bay details',
 (tester) async {
  var revoked=false;
  await mount(tester,GarageCalendarSettingsScreen(
    loadHours:() async=>[],
    loadResources:() async=>[
      const GarageCalendarResource(id:bayId,name:'Inspection Bay',
        active:true,mechanicUserId:mechanicId),
    ],
    setHours:(day,open,close,enabled) async=>true,
    addResource:(name) async=>bayId,
    setResourceActive:(id,active) async=>true,
    loadMechanics:() async {
      if(revoked)throw StateError('Owner permission removed');
      return [member];
    },
    assignMechanic:(id,staff) async=>true,
  ));
  await findBay(tester);
  expect(find.text('mechanic@example.test'),findsOneWidget);
  revoked=true;
  await tester.tap(find.byKey(const Key('garage_settings_refresh')));
  await tester.pumpAndSettle();
  expect(find.text('mechanic@example.test'),findsNothing);
  expect(find.text('Inspection Bay'),findsNothing);
  expect(find.byKey(const Key('garage_settings_notice')),findsOneWidget);
 });
}
