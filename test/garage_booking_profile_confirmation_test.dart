import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_profile_screen.dart';

import 'garage_booking_profile_test.dart' as fixture;

Future<VoidCallback> saveAction(WidgetTester tester) async {
  final button = find.byKey(const Key('booking_profile_save'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  return tester.widget<FilledButton>(button).onPressed!;
}

void main() {
  setUp(() {
    AppLocale.language.value = 'en';
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previous);
  });
  tearDown(() => AppLocale.language.value = 'en');

  for (final outcome in ['saved', 'rejected', 'throws']) {
    testWidgets('profile uses one confirmation intent for $outcome', (tester) async {
      var writes = 0;
      final values = <String>[];
      await tester.pumpWidget(MaterialApp(home: GarageBookingProfileScreen(
        load: () async => fixture.profile(),
        save: ({required city, required timeZone, required services,
            required durationMinutes, required listed}) async {
          writes++;
          values.add(city);
          if (outcome == 'throws') throw StateError('Private backend detail');
          return outcome == 'saved';
        },
      )));
      await tester.pumpAndSettle();
      final save = await saveAction(tester);
      save(); save(); save();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(writes, 0);
      await tester.tap(find.byKey(const Key('booking_profile_confirm')));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(values, ['Dunstable']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Private backend detail'), findsNothing);
      // An uncertain response still requires an explicit successful reload.
      await tester.tap(find.byKey(const Key('booking_profile_reload')));
      await tester.pumpAndSettle();
      final next = await saveAction(tester);
      next(); next();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final dismissal in ['back', 'barrier', 'navigator']) {
    testWidgets('profile confirmation unlocks after $dismissal', (tester) async {
      var writes = 0;
      await tester.pumpWidget(MaterialApp(home: GarageBookingProfileScreen(
        load: () async => fixture.profile(),
        save: ({required city, required timeZone, required services,
            required durationMinutes, required listed}) async { writes++; return true; },
      )));
      await tester.pumpAndSettle();
      final save = await saveAction(tester);
      save(); save();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      if (dismissal == 'back') {
        await tester.tap(find.text('Back'));
      } else if (dismissal == 'barrier') {
        await tester.tapAt(const Offset(8, 80));
      } else {
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes, 0);
      save(); save();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('booking_profile_confirm')));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
