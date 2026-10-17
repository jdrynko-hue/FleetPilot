import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_profile_screen.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/profile_visibility_text.dart';

GarageBookingProfile profile(bool listed) => GarageBookingProfile(
  workspaceId: '00000000-0000-4000-8000-000000000001', city: 'Dunstable',
  timeZone: 'Europe/London', services: const ['brakes'], durationMinutes: 60, listed: listed);

void main() {
  tearDown(() => AppLocale.language.value = 'en');
  Future<void> top(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, 1600));
    await tester.pumpAndSettle();
  }
  Future<void> confirmSave(WidgetTester tester) async {
    final save = find.byKey(const Key('booking_profile_save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking_profile_confirm')));
    await tester.pumpAndSettle();
  }
  test('visibility copy covers all supported languages', () {
    expect(BookingVisibilityText.translations.keys.toSet(), supportedLanguages.toSet());
    for (final row in BookingVisibilityText.translations.values) {
      expect(row.length, 2);
      expect(row[0], isNot(row[1]));
    }
  });
  for (final language in supportedLanguages) {
    testWidgets('unsaved visibility switch never changes saved status at 320px in $language', (tester) async {
      AppLocale.language.value = language;
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var writes = 0;
      await tester.pumpWidget(MaterialApp(home: GarageBookingProfileScreen(
        load: () async => profile(false),
        save: ({required city, required timeZone, required services, required durationMinutes, required listed}) async {
          writes++; return true;
        })));
      await tester.pumpAndSettle();
      expect(find.text(BookingVisibilityText.saved(false)), findsOneWidget);
      final toggle = find.byKey(const Key('booking_profile_listed'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await top(tester);
      expect(find.text(BookingVisibilityText.saved(false)), findsOneWidget);
      expect(find.text(BookingVisibilityText.saved(true)), findsNothing);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('saved visibility follows authoritative reload, not requested value', (tester) async {
    var serverListed = false;
    var writes = 0;
    await tester.pumpWidget(MaterialApp(home: GarageBookingProfileScreen(
      load: () async => profile(serverListed),
      save: ({required city, required timeZone, required services, required durationMinutes, required listed}) async {
        writes++; return true;
      })));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('booking_profile_listed'));
    await tester.ensureVisible(toggle); await tester.tap(toggle); await tester.pump();
    await confirmSave(tester);
    await top(tester);
    expect(writes, 1);
    expect(find.text(BookingVisibilityText.saved(false)), findsOneWidget);
    serverListed = true;
    await tester.tap(find.byKey(const Key('booking_profile_reload')));
    await tester.pumpAndSettle();
    expect(find.text(BookingVisibilityText.saved(true)), findsOneWidget);
  });
  testWidgets('uncertain save removes saved visibility until a successful reload', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GarageBookingProfileScreen(
      load: () async => profile(true),
      save: ({required city, required timeZone, required services, required durationMinutes, required listed}) async {
        throw StateError('synthetic timeout');
      })));
    await tester.pumpAndSettle();
    expect(find.text(BookingVisibilityText.saved(true)), findsOneWidget);
    await confirmSave(tester);
    expect(find.byKey(const Key('booking_profile_saved_visibility')), findsNothing);
    await tester.tap(find.byKey(const Key('booking_profile_reload')));
    await tester.pumpAndSettle();
    expect(find.text(BookingVisibilityText.saved(true)), findsOneWidget);
  });
}
