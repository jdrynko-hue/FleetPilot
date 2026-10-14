import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/calendar_settings_screen.dart';
import 'package:fleetpilot/garage/resource_calendar_repository.dart';

const resourceId='00000000-0000-4000-8000-000000000101';
final monday=GarageOpeningHours(isoWeekday:1,
  opensAt:'08:00:00',closesAt:'17:00:00');
const bay=GarageCalendarResource(id:resourceId,name:'Existing Bay',active:true);

Future<void> render(WidgetTester tester,Widget screen,{double width=375}) async {
 tester.view.physicalSize=Size(width,840);
 tester.view.devicePixelRatio=1;
 addTearDown(tester.view.resetPhysicalSize);
 addTearDown(tester.view.resetDevicePixelRatio);
 await tester.pumpWidget(MaterialApp(home:screen));
 await tester.pumpAndSettle();
}

void main(){
  setUp(()=>AppLocale.language.value='en');
  tearDown(()=>AppLocale.language.value='en');

  for(final width in [320.0,375.0,900.0]){
    testWidgets('workshop owner can view opening hours and bays at $width',
      (tester) async {
      await render(tester,GarageCalendarSettingsScreen(
        loadHours:() async=>[monday],
        loadResources:() async=>[bay],
        setHours:(day,opens,closes,enabled) async=>true,
        addResource:(name) async=>resourceId,
        setResourceActive:(id,active) async=>true,
      ),width:width);
      expect(find.text('Monday'),findsOneWidget);
      expect(find.text('Existing Bay'),findsOneWidget);
      expect(find.byKey(const Key('garage_settings_add_bay')),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }

  testWidgets('adding a bay waits for confirmation and refetches resources',
    (tester) async {
    var added=false;
    var created=0;
    await render(tester,GarageCalendarSettingsScreen(
      loadHours:() async=>[monday],
      loadResources:() async=>added
        ?[bay,const GarageCalendarResource(
          id:'00000000-0000-4000-8000-000000000102',
          name:'New Inspection Bay',active:true)]
        :[bay],
      setHours:(day,opens,closes,enabled) async=>true,
      addResource:(name) async {
        expect(name,'New Inspection Bay');
        created++;
        added=true;
        return '00000000-0000-4000-8000-000000000102';
      },
      setResourceActive:(id,active) async=>true,
    ));
    await tester.ensureVisible(find.byKey(const Key('garage_settings_add_bay')));
    await tester.tap(find.byKey(const Key('garage_settings_add_bay')));
    await tester.pumpAndSettle();
    expect(created,0);
    await tester.enterText(find.byKey(const Key('garage_resource_name')),
      'New Inspection Bay');
    await tester.tap(find.byKey(const Key('garage_resource_save')));
    await tester.pumpAndSettle();
    expect(created,1);
    expect(find.text('New Inspection Bay'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('owner closing Monday only changes schedule after consent',
    (tester) async {
    var enabled=true;
    var changes=0;
    await render(tester,GarageCalendarSettingsScreen(
      loadHours:() async=>enabled?[monday]:[],
      loadResources:() async=>[bay],
      setHours:(day,opens,closes,newEnabled) async {
        expect(day,1);
        expect(newEnabled,false);
        changes++;
        enabled=false;
        return true;
      },
      addResource:(name) async=>resourceId,
      setResourceActive:(id,active) async=>true,
    ));
    await tester.tap(find.byKey(const Key('garage_settings_weekday_1')));
    await tester.pumpAndSettle();
    expect(changes,0);
    await tester.tap(find.byKey(const Key('garage_hours_close_day')));
    await tester.pumpAndSettle();
    expect(changes,1);
    expect(find.text('Closed'),findsWidgets);
    expect(tester.takeException(),isNull);
  });

  testWidgets('backend forbids disabling a booked bay; notice remains',
    (tester) async {
    await render(tester,GarageCalendarSettingsScreen(
      loadHours:() async=>[monday],
      loadResources:() async=>[bay],
      setHours:(day,opens,closes,enabled) async=>true,
      addResource:(name) async=>resourceId,
      setResourceActive:(id,active) async {
        expect(id,resourceId);
        expect(active,false);
        throw StateError('Future booking exists');
      },
    ));
    await tester.ensureVisible(
      find.byKey(Key('garage_settings_toggle_'+resourceId)));
    await tester.tap(find.byKey(Key('garage_settings_toggle_'+resourceId)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_resource_confirm_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Existing Bay'),findsOneWidget);
    expect(find.byKey(const Key('garage_settings_notice')),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('permission revocation removes stale staff resource details',
    (tester) async {
    var denied=false;
    await render(tester,GarageCalendarSettingsScreen(
      loadHours:() async=>[monday],
      loadResources:() async {
        if(denied)throw StateError('Access revoked');
        return [bay];
      },
      setHours:(day,opens,closes,enabled) async=>true,
      addResource:(name) async=>resourceId,
      setResourceActive:(id,active) async=>true,
    ));
    expect(find.text('Existing Bay'),findsOneWidget);
    denied=true;
    await tester.tap(find.byKey(const Key('garage_settings_refresh')));
    await tester.pumpAndSettle();
    expect(find.text('Existing Bay'),findsNothing);
    expect(find.byKey(const Key('garage_settings_notice')),findsOneWidget);
  });
}
