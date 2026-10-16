import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_status_text.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'package:fleetpilot/garage/resource_calendar_repository.dart';
import 'package:fleetpilot/garage/resource_calendar_screen.dart';
import 'garage_resource_calendar_screen_test.dart' as fixture;

GarageBookingNotice notice({bool read = false, String event = 'confirmed'}) => GarageBookingNotice(
  id: fixture.noticeId, bookingId: fixture.requestId, event: event,
  occurredAt: DateTime.utc(2026, 11, 20, 10),
  readAt: read ? DateTime.utc(2026, 11, 20, 11) : null);

void main() {
  tearDown(() => AppLocale.language.value = 'en');
  for (final locale in supportedLanguages) {
    test('notification event allowlist uses localized labels in $locale', () {
      const mapping = {'requested':'bookingRequested', 'confirmed':'bookingConfirmed',
        'declined':'bookingDeclined', 'withdrawn':'bookingWithdrawn',
        'cancellation_requested':'bookingCancellationPending', 'cancelled':'bookingCancelled'};
      for (final entry in mapping.entries) {
        expect(bookingNoticeLabel(entry.key, language: locale),
          GarageUiText.get(entry.value, language: locale));
      }
      expect(bookingNoticeLabel('PRIVATE_UNTRUSTED_EVENT', language: locale),
        GarageUiText.get('noticeEventUnknown', language: locale));
    });
    testWidgets('localized notification read keeps its ID and fits 320px in $locale', (tester) async {
      AppLocale.language.value = locale;
      var read = false;
      var calls = 0;
      await fixture.mount(tester, GarageBookingNotificationsScreen(
        load: () async => [notice(read: read)],
        acknowledge: (id) async { expect(id, fixture.noticeId); calls++; read = true; return true; }), width: 320);
      expect(find.text(bookingNoticeLabel('confirmed')), findsOneWidget);
      expect(find.text('confirmed'), findsNothing);
      expect(find.text(GarageUiText.get('noticeDisclaimer')), findsOneWidget);
      expect(find.byTooltip(GarageUiText.get('refresh')), findsOneWidget);
      await tester.tap(find.byKey(Key('garage_notification_mark_${fixture.noticeId}')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byKey(Key('garage_notification_mark_${fixture.noticeId}')), findsNothing);
      expect(find.byKey(const Key('garage_notifications_error')), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('failed notification refresh hides old data without empty claim in $locale', (tester) async {
      AppLocale.language.value = locale;
      var failed = false;
      await fixture.mount(tester, GarageBookingNotificationsScreen(
        load: () async {
          if (failed) throw StateError('Synthetic revoked access');
          return [notice(event: 'PRIVATE_UNTRUSTED_EVENT')];
        }, acknowledge: (_) async => fail('No acknowledgement after failure')), width: 320);
      expect(find.text(GarageUiText.get('noticeEventUnknown')), findsOneWidget);
      expect(find.text('PRIVATE_UNTRUSTED_EVENT'), findsNothing);
      failed = true;
      await tester.tap(find.byKey(const Key('garage_notifications_refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('garage_notification_${fixture.noticeId}')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('garage_notifications_error'))).data,
        GarageUiText.get('noticeLoadFailed'));
      expect(find.byKey(const Key('garage_notifications_empty')), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('uncertain read reloads authoritative notification state in $locale', (tester) async {
      AppLocale.language.value = locale;
      var loads = 0;
      var calls = 0;
      await fixture.mount(tester, GarageBookingNotificationsScreen(
        load: () async { loads++; return [notice(read: loads > 1)]; },
        acknowledge: (_) async { calls++; throw TimeoutException('Synthetic uncertainty'); }), width: 320);
      await tester.tap(find.byKey(Key('garage_notification_mark_${fixture.noticeId}')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(loads, 2);
      expect(tester.widget<Text>(find.byKey(const Key('garage_notifications_error'))).data,
        GarageUiText.get('noticeReadUnconfirmed'));
      expect(find.byKey(Key('garage_notification_mark_${fixture.noticeId}')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
