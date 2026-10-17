import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_profile_screen.dart';

import 'garage_booking_profile_test.dart' as fixture;

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  for (final replacement in ['workspace', 'refresh', 'dispose']) {
    testWidgets('old profile controls cannot act after $replacement', (tester) async {
      var oldLoads = 0;
      var newLoads = 0;
      var writes = 0;
      Future<void> mount({required bool newScope}) => tester.pumpWidget(
        MaterialApp(home: GarageBookingProfileScreen(
          load: () async {
            if (newScope) { newLoads++; } else { oldLoads++; }
            return fixture.profile();
          },
          save: ({required city, required timeZone, required services,
              required durationMinutes, required listed}) async {
            writes++;
            return true;
          },
        )),
      );
      await mount(newScope: false);
      await tester.pumpAndSettle();
      final oldSave = tester.widget<FilledButton>(
        find.byKey(const Key('booking_profile_save'))).onPressed!;
      final oldReload = tester.widget<IconButton>(
        find.byKey(const Key('booking_profile_reload'))).onPressed!;
      if (replacement == 'workspace') {
        await mount(newScope: true);
      } else if (replacement == 'refresh') {
        oldReload();
      } else {
        await tester.pumpWidget(const MaterialApp(home: Text('Signed out')));
      }
      await tester.pumpAndSettle();
      final loadsBefore = oldLoads + newLoads;
      oldSave(); oldReload();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(oldLoads + newLoads, loadsBefore);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      if (replacement != 'dispose') {
        final freshSave = tester.widget<FilledButton>(
          find.byKey(const Key('booking_profile_save'))).onPressed!;
        freshSave();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop(true);
        await tester.pumpAndSettle();
        expect(writes, 1);
      }
    });
  }
}
