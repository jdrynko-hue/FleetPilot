import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/resource_calendar_screen.dart';

import 'garage_resource_calendar_screen_test.dart' as fixture;

Future<VoidCallback> selectBay(WidgetTester tester,
    {String bookingId = fixture.requestId}) async {
  final selector = find.byKey(
      Key('garage_calendar_select_$bookingId'));
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bay Two').last);
  await tester.pumpAndSettle();
  final button = find.byKey(
      Key('garage_calendar_accept_$bookingId'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  return tester.widget<FilledButton>(button).onPressed!;
}

void main() {
  setUp(() {
    AppLocale.language.value = 'en';
    final previousFatal = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previousFatal);
  });
  tearDown(() => AppLocale.language.value = 'en');

  for (final outcome in ['confirmed', 'rejected', 'throws']) {
    testWidgets('calendar serializes rapid confirmation intents: $outcome',
        (tester) async {
      final writes = <List<String>>[];
      var loads = 0;
      await fixture.mount(tester, GarageResourceCalendarScreen(
        loadResources: () async => fixture.resources,
        loadRequests: () async { loads++; return [fixture.req()]; },
        loadCalendar: () async => [],
        confirmSlot: (booking, bay) async {
          writes.add([booking, bay]);
          if (outcome == 'throws') throw StateError('private failure');
          return outcome;
        },
      ), width: 320);
      final action = await selectBay(tester);
      action(); action(); action();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(writes, isEmpty);
      await tester.tap(find.byKey(const Key('calendar_confirm_action')));
      await tester.pumpAndSettle();
      expect(writes, [[fixture.requestId, fixture.bay2]]);
      expect(loads, 2);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('private failure'), findsNothing);
      expect(find.byKey(const Key('garage_calendar_error')),
          outcome == 'confirmed' ? findsNothing : findsOneWidget);
      // A completed or failed write must not leave the dialog-intent lock stuck.
      final next = await selectBay(tester);
      next();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop(false);
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  for (final dismissal in ['back', 'barrier', 'navigator']) {
    testWidgets('calendar releases confirmation lock after $dismissal dismissal',
        (tester) async {
      var writes = 0;
      await fixture.mount(tester, GarageResourceCalendarScreen(
        loadResources: () async => fixture.resources,
        loadRequests: () async => [fixture.req()],
        loadCalendar: () async => [],
        confirmSlot: (booking, bay) async { writes++; return 'confirmed'; },
      ));
      final action = await selectBay(tester);
      action(); action();
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
      action(); action();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_confirm_action')));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('calendar refresh invalidates dialog and permits a fresh intent',
      (tester) async {
    var writes = 0;
    var loads = 0;
    await fixture.mount(tester, GarageResourceCalendarScreen(
      loadResources: () async => fixture.resources,
      loadRequests: () async { loads++; return [fixture.req()]; },
      loadCalendar: () async => [],
      confirmSlot: (booking, bay) async { writes++; return 'confirmed'; },
    ));
    final action = await selectBay(tester);
    final refresh = tester.widget<IconButton>(
        find.byKey(const Key('garage_calendar_refresh'))).onPressed!;
    action(); action();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    refresh();
    await tester.pumpAndSettle();
    expect(loads, 2);
    await tester.tap(find.byKey(const Key('calendar_confirm_action')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    final next = await selectBay(tester);
    next();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('calendar_confirm_action')));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar serializes intents across two different bookings',
      (tester) async {
    const secondId = '00000000-0000-4000-8000-000000000105';
    final second = GarageBookingInboxItem(
      id: secondId, customerName: 'Second Person',
      customerEmail: 'second@example.test', vehicleMake: 'Ford',
      vehicleModel: 'Transit', service: 'brakes', concern: 'Check brakes',
      startAt: DateTime.utc(2026, 11, 20, 12), durationMinutes: 60,
      status: GarageBookingStatus.requested,
    );
    final writes = <List<String>>[];
    await fixture.mount(tester, GarageResourceCalendarScreen(
      loadResources: () async => fixture.resources,
      loadRequests: () async => [fixture.req(), second],
      loadCalendar: () async => [],
      confirmSlot: (booking, bay) async {
        writes.add([booking, bay]); return 'confirmed';
      },
    ));
    final first = await selectBay(tester);
    await tester.scrollUntilVisible(
        find.byKey(const Key('garage_calendar_select_$secondId')), 200);
    final other = await selectBay(tester, bookingId: secondId);
    first(); other();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(writes, isEmpty);
    await tester.tap(find.byKey(const Key('calendar_confirm_action')));
    await tester.pumpAndSettle();
    expect(writes, [[fixture.requestId, fixture.bay2]]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
