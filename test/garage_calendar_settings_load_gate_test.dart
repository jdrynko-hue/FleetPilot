import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/calendar_settings_screen.dart';
import 'package:fleetpilot/garage/resource_calendar_repository.dart';
import 'garage_calendar_settings_screen_test.dart' as fixture;

void main() {
  for (final stage in ['hours', 'bays', 'mechanics']) {
    for (final initialFailure in [false, true]) {
      testWidgets('$stage failure blocks calendar editing until reload (initial=$initialFailure)', (tester) async {
        var failed = initialFailure;
        var writes = 0;
        await fixture.render(tester, GarageCalendarSettingsScreen(
          loadHours: () async {
            if (failed && stage == 'hours') throw StateError('Synthetic hours failure');
            return [fixture.monday];
          },
          loadResources: () async {
            if (failed && stage == 'bays') throw StateError('Synthetic resources failure');
            return [fixture.bay];
          },
          loadMechanics: () async {
            if (failed && stage == 'mechanics') throw StateError('Synthetic roster failure');
            return <GarageRosterMechanic>[];
          },
          setHours: (day, opens, closes, enabled) async {
            writes++;
            expect(day, 1);
            expect(enabled, false);
            return true;
          },
          addResource: (_) async { writes++; return fixture.resourceId; },
          setResourceActive: (_, __) async { writes++; return true; },
          assignMechanic: (_, __) async { writes++; return true; }), width: 320);
        if (!initialFailure) {
          expect(find.text('Monday'), findsOneWidget);
          failed = true;
          await tester.tap(find.byKey(const Key('garage_settings_refresh')));
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const Key('garage_settings_notice')), findsOneWidget);
        expect(find.byKey(const Key('garage_settings_weekday_1')), findsNothing);
        expect(find.text('Closed'), findsNothing);
        expect(find.text('Existing Bay'), findsNothing);
        expect(find.byKey(const Key('garage_settings_add_bay')), findsNothing);
        expect(find.byKey(Key('garage_settings_toggle_${fixture.resourceId}')), findsNothing);
        expect(find.byKey(Key('garage_settings_assign_${fixture.resourceId}')), findsNothing);
        expect(writes, 0);
        failed = false;
        await tester.tap(find.byKey(const Key('garage_settings_refresh')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('garage_settings_notice')), findsNothing);
        expect(find.text('Monday'), findsOneWidget);
        await tester.tap(find.byKey(const Key('garage_settings_weekday_1')));
        await tester.pumpAndSettle();
        expect(writes, 0);
        await tester.tap(find.byKey(const Key('garage_hours_close_day')));
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
