import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_status_text.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'package:fleetpilot/garage/resource_calendar_repository.dart';
import 'package:fleetpilot/garage/resource_calendar_screen.dart';

import 'garage_resource_calendar_screen_test.dart' as fixture;

void main() {
  tearDown(() => AppLocale.language.value = 'en');

  for (final locale in supportedLanguages) {
    testWidgets('calendar $locale at 320px localizes service and confirmation',
        (tester) async {
      AppLocale.language.value = locale;
      var writes = 0;
      await fixture.mount(tester, GarageResourceCalendarScreen(
        loadResources: () async => fixture.resources,
        loadRequests: () async => [fixture.req()],
        loadCalendar: () async => [],
        confirmSlot: (_, __) async { writes++; return 'confirmed'; },
      ), width: 320);
      expect(find.text(GarageUiText.get('calendarTitle')), findsOneWidget);
      expect(find.byTooltip(GarageUiText.get('refresh')), findsOneWidget);
      expect(find.text('${bookingServiceLabel('brakes')} — Ford Focus'),
          findsOneWidget);
      expect(find.text('brakes — Ford Focus'), findsNothing);
      final select = find.byKey(
          const Key('garage_calendar_select_' + fixture.requestId));
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bay Two').last);
      await tester.pumpAndSettle();
      final accept = find.byKey(
          const Key('garage_calendar_accept_' + fixture.requestId));
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(find.text(GarageUiText.get('calendarCheck')), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog),
        matching: find.text(GarageUiText.get('calendarConfirmTitle'))),
        findsOneWidget);
      expect(writes, 0);
      await tester.tap(find.text(GarageUiText.get('quoteBack')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('calendar $locale localizes private load errors and empty state',
        (tester) async {
      AppLocale.language.value = locale;
      await fixture.mount(tester, GarageResourceCalendarScreen(
        loadResources: () async => throw StateError('private server detail'),
        loadRequests: () async => [fixture.req()],
        loadCalendar: () async => [],
        confirmSlot: (_, __) async => 'confirmed',
      ), width: 320);
      expect(find.text(GarageUiText.get('calendarLoadError')), findsOneWidget);
      expect(find.text(GarageUiText.get('calendarAddBay')), findsOneWidget);
      expect(find.textContaining('private server detail'), findsNothing);
      expect(find.text('Booking Person'), findsNothing);
      await tester.scrollUntilVisible(
          find.byKey(const Key('garage_calendar_empty')), 200);
      expect(find.text(GarageUiText.get('calendarEmpty')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('calendar $locale localizes rejected confirmation', (tester) async {
      AppLocale.language.value = locale;
      var writes = 0;
      await fixture.mount(tester, GarageResourceCalendarScreen(
        loadResources: () async => fixture.resources,
        loadRequests: () async => [fixture.req()],
        loadCalendar: () async => [],
        confirmSlot: (_, __) async { writes++; return 'rejected'; },
      ), width: 320);
      final select = find.byKey(
          const Key('garage_calendar_select_' + fixture.requestId));
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bay Two').last);
      await tester.pumpAndSettle();
      final accept = find.byKey(
          const Key('garage_calendar_accept_' + fixture.requestId));
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('calendar_confirm_action')));
      await tester.pumpAndSettle();
      expect(writes, 1);
      await tester.scrollUntilVisible(
          find.byKey(const Key('garage_calendar_error')), -200);
      expect(find.text(GarageUiText.get('calendarConfirmFailed')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long bay names fit the selected dropdown on a 320px screen',
      (tester) async {
    AppLocale.language.value = 'pl';
    final longName = List.filled(12, 'Stanowisko ciężarówek').join(' ');
    await fixture.mount(tester, GarageResourceCalendarScreen(
      loadResources: () async => [
        GarageCalendarResource(id: fixture.bay1, name: longName, active: true),
      ],
      loadRequests: () async => [fixture.req()],
      loadCalendar: () async => [],
      confirmSlot: (_, __) async => 'confirmed',
    ), width: 320);
    final select = find.byKey(
        const Key('garage_calendar_select_' + fixture.requestId));
    await tester.scrollUntilVisible(select, 250);
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text(longName).last);
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButton<String>>(find.descendant(
        of: select, matching: find.byType(DropdownButton<String>)));
    expect(dropdown.isExpanded, isTrue);
    final selected = dropdown.items!.single.child as Text;
    expect(selected.overflow, TextOverflow.ellipsis);
    expect(selected.maxLines, 1);
    expect(tester.takeException(), isNull);
  });
}
