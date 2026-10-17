import 'dart:async';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_profile_screen.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const workspace = '00000000-0000-4000-8000-000000000101';
Map<String, Object> row() => {'workspace_id':workspace,'city':'Dunstable',
  'time_zone':'Europe/London','services':['brakes'],'duration_minutes':60,'listed':false};
GarageBookingProfile profile({bool listed = false}) => GarageBookingProfile(
  workspaceId:workspace,city:'Dunstable',timeZone:'Europe/London',
  services:const ['brakes'],durationMinutes:60,listed:listed);

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');
  test('profile parsing is owner scoped, typed and immutable', () {
    expect(GarageBookingRepository.parseProfile([],workspace),isNull);
    final parsed = GarageBookingRepository.parseProfile([row()],workspace)!;
    expect(parsed.listed,false); expect(parsed.city,'Dunstable');
    expect(() => parsed.services.clear(),throwsUnsupportedError);
    for (final invalid in <Object?>[null,{},[row(),row()],['bad'],
      [{...row(),'workspace_id':'00000000-0000-4000-8000-000000000102'}],
      [{...row(),'services':['brakes','brakes']}], [{...row(),'services':['unknown']}],
      [{...row(),'services':[]}], [{...row(),'duration_minutes':45}],
      [{...row(),'listed':'true'}], [{...row(),'city':'A'}]]) {
      expect(() => GarageBookingRepository.parseProfile(invalid,workspace),throwsFormatException);
    }
  });
  Future<void> show(WidgetTester tester, GarageBookingProfileScreen screen) async {
    await tester.pumpWidget(MaterialApp(home:screen)); await tester.pumpAndSettle();
  }
  Future<void> pressSave(WidgetTester tester) async {
    final save = find.byKey(const Key('booking_profile_save'));
    await tester.ensureVisible(save); await tester.pumpAndSettle();
    await tester.tap(save); await tester.pumpAndSettle();
  }
  testWidgets('listing stays off until explicit confirmed save', (tester) async {
    var writes = 0;
    var saved = false;
    await show(tester, GarageBookingProfileScreen(
      load: () async => profile(listed:saved),
      save: ({required city,required timeZone,required services,required durationMinutes,required listed}) async {
        writes++; expect(city,'Dunstable'); expect(timeZone,'Europe/London');
        expect(services,['brakes']); expect(durationMinutes,60); expect(listed,true);
        saved=true; return true;
      }));
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('booking_profile_listed'))).value,false);
    await tester.ensureVisible(find.byKey(const Key('booking_profile_listed')));
    await tester.tap(find.byKey(const Key('booking_profile_listed'))); await tester.pump();
    await pressSave(tester); expect(writes,0);
    await tester.tap(find.byKey(const Key('booking_profile_confirm'))); await tester.pumpAndSettle();
    expect(writes,1); expect(find.text('Profile saved.'),findsOneWidget);
  });
  testWidgets('uncertain save blocks retries until successful profile reload', (tester) async {
    var writes=0;
    await show(tester,GarageBookingProfileScreen(load:() async => profile(),
      save:({required city,required timeZone,required services,required durationMinutes,required listed}) async {
        writes++; throw StateError('PRIVATE DETAIL');
      }));
    await pressSave(tester);
    await tester.tap(find.byKey(const Key('booking_profile_confirm'))); await tester.pumpAndSettle();
    expect(writes,1); expect(find.textContaining('PRIVATE DETAIL'),findsNothing);
    expect(find.byKey(const Key('booking_profile_save')),findsNothing);
    expect(find.byKey(const Key('booking_profile_city')),findsNothing);
    await tester.tap(find.byKey(const Key('booking_profile_reload'))); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('booking_profile_save'))); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('booking_profile_save'))).onPressed,isNotNull);
  });
  testWidgets('access failure cannot expose a previously loaded profile', (tester) async {
    var denied=false;
    await show(tester,GarageBookingProfileScreen(load:() async {
      if(denied) throw StateError('PRIVATE DETAIL'); return profile();
    }, save:({required city,required timeZone,required services,required durationMinutes,required listed}) async => true));
    denied=true;
    await tester.tap(find.byKey(const Key('booking_profile_reload'))); await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking_profile_city')),findsNothing);
    expect(find.byKey(const Key('booking_profile_save')),findsNothing);
    expect(find.textContaining('PRIVATE DETAIL'),findsNothing);
  });
  for (final fails in [false,true]) {
    testWidgets('old profile save cannot affect a replacement workshop (error=$fails)', (tester) async {
      final pending=Completer<bool>();
      var newLoads=0;
      await show(tester,GarageBookingProfileScreen(load:() async => profile(),
        save:({required city,required timeZone,required services,required durationMinutes,required listed}) => pending.future));
      await pressSave(tester);
      await tester.tap(find.byKey(const Key('booking_profile_confirm'))); await tester.pump();
      await show(tester,GarageBookingProfileScreen(load:() async {newLoads++;return null;},
        save:({required city,required timeZone,required services,required durationMinutes,required listed}) async => true));
      if(fails) {pending.completeError(StateError('old failure'));} else {pending.complete(true);}
      await tester.pumpAndSettle(); expect(newLoads,1);
      expect(find.byKey(const Key('booking_profile_notice')),findsNothing);
      expect(tester.widget<TextField>(find.byKey(const Key('booking_profile_city'))).controller!.text,isEmpty);
    });
  }
  testWidgets('profile dialog cannot save after workshop scope replacement', (tester) async {
    var oldWrites=0, newWrites=0;
    await show(tester,GarageBookingProfileScreen(load:() async => profile(),
      save:({required city,required timeZone,required services,required durationMinutes,required listed}) async {oldWrites++;return true;}));
    await pressSave(tester);
    await show(tester,GarageBookingProfileScreen(load:() async => null,
      save:({required city,required timeZone,required services,required durationMinutes,required listed}) async {newWrites++;return true;}));
    await tester.tap(find.byKey(const Key('booking_profile_confirm'))); await tester.pumpAndSettle();
    expect(oldWrites,0); expect(newWrites,0); expect(tester.takeException(),isNull);
  });
  testWidgets('old profile load cannot restore previous workshop details', (tester) async {
    final pending=Completer<GarageBookingProfile?>();
    await tester.pumpWidget(MaterialApp(home:GarageBookingProfileScreen(load:() => pending.future,
      save:({required city,required timeZone,required services,required durationMinutes,required listed}) async => true)));
    await tester.pump();
    await show(tester,GarageBookingProfileScreen(load:() async => null,
      save:({required city,required timeZone,required services,required durationMinutes,required listed}) async => true));
    pending.complete(profile(listed:true)); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('booking_profile_city'))).controller!.text,isEmpty);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('booking_profile_listed'))).value,false);
  });
  for(final locale in GarageUiText.labels.keys) {
    testWidgets('new profile defaults to unlisted and fits phone in $locale', (tester) async {
      AppLocale.language.value=locale;
      tester.view.physicalSize=const Size(320,844); tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await show(tester,GarageBookingProfileScreen(load:() async => null,
        save:({required city,required timeZone,required services,required durationMinutes,required listed}) async => true));
      final toggle=find.byKey(const Key('booking_profile_listed'));
      await tester.scrollUntilVisible(toggle,300,scrollable:find.byType(Scrollable).first);
      await tester.pumpAndSettle(); expect(tester.widget<SwitchListTile>(toggle).value,false);
      expect(tester.takeException(),isNull);
    });
  }
}
