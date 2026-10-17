import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/resource_calendar_repository.dart';
import 'package:fleetpilot/garage/resource_calendar_screen.dart';

import 'garage_resource_calendar_screen_test.dart' as fixture;

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  for (final replacement in ['account', 'refresh', 'read', 'removed', 'dispose']) {
    testWidgets('notification controls reject stale activation after $replacement',
        (tester) async {
      var loads = 0;
      var oldReads = 0;
      var newReads = 0;
      var read = false;
      var removed = false;
      Future<void> mount({required bool newAccount}) => tester.pumpWidget(
        MaterialApp(home: GarageBookingNotificationsScreen(
          load: () async {
            loads++;
            return removed ? [] : [GarageBookingNotice(
              id: fixture.noticeId, bookingId: fixture.requestId,
              event: 'confirmed', occurredAt: DateTime.utc(2026, 11, 20, 10),
              readAt: read ? DateTime.utc(2026, 11, 20, 11) : null,
            )];
          },
          acknowledge: (_) async {
            if (newAccount) { newReads++; } else { oldReads++; }
            read = true;
            return true;
          },
        )),
      );
      await mount(newAccount: false);
      await tester.pumpAndSettle();
      final markKey = Key('garage_notification_mark_${fixture.noticeId}');
      final oldMark = tester.widget<TextButton>(find.byKey(markKey)).onPressed!;
      final oldRefresh = tester.widget<IconButton>(
        find.byKey(const Key('garage_notifications_refresh'))).onPressed!;
      if (replacement == 'account') {
        // Reusing the synthetic ID verifies scope, not just ID membership.
        await mount(newAccount: true);
      } else if (replacement == 'dispose') {
        await tester.pumpWidget(const MaterialApp(home: Text('Signed out')));
      } else {
        read = replacement == 'read';
        removed = replacement == 'removed';
        oldRefresh();
      }
      await tester.pumpAndSettle();
      final loadsBefore = loads;
      oldMark(); oldRefresh();
      await tester.pumpAndSettle();
      expect(oldReads, 0);
      expect(newReads, 0);
      expect(loads, loadsBefore);
      expect(find.byKey(const Key('garage_notifications_error')), findsNothing);
      expect(tester.takeException(), isNull);
      if (replacement == 'account' || replacement == 'refresh') {
        final currentMark = tester.widget<TextButton>(find.byKey(markKey)).onPressed!;
        currentMark(); currentMark();
        await tester.pumpAndSettle();
        expect(oldReads, replacement == 'account' ? 0 : 1);
        expect(newReads, replacement == 'account' ? 1 : 0);
        expect(find.byKey(markKey), findsNothing);
      } else {
        expect(find.byKey(markKey), findsNothing);
      }
    });
  }
}
