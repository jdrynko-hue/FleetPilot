import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/booking_recovery_journal.dart';
import 'package:fleetpilot/garage/booking_status_text.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'booking_recovery_journal_test.dart' as journal;
import 'garage_booking_screens_test.dart' as fixture;
import 'garage_booking_request_locales_test.dart' as fields;

final marker = PendingBookingRequest(actorId: journal.actor,
  workspaceId: fixture.shop.workspaceId, requestKey: journal.requestKey,
  createdAt: DateTime.utc(2026));
final BookingSearch search = ({city}) async => [fixture.shop];
final BookingSubmit neverSubmit = ({required workspaceId, required customerName,
  required vehicleMake, required vehicleModel, required service, required concern,
  required desiredStart, required requestKey, registration}) async {
  fail('Recovery must never submit a booking automatically');
};

void main() {
  tearDown(() => AppLocale.language.value = 'en');
  for (final language in supportedLanguages) {
    testWidgets('restored pending attempt requires explicit recovery at 320px in $language', (tester) async {
      AppLocale.language.value = language;
      var pending = [marker];
      var resolves = 0, histories = 0;
      await fixture.render(tester, GarageBookingSearchScreen(search: search,
        submit: neverSubmit, pendingRequests: () => pending,
        onViewBookings: () => histories++, resolveRequest: (request) async {
          expect(request.requestKey, marker.requestKey);
          resolves++;
          pending = [];
          return const BookingRecoveryOutcome(bookingId: fixture.bookingId,
            status: GarageBookingStatus.withdrawn);
        }), width: 320);
      expect(resolves, 0);
      expect(find.byKey(const Key('booking_pending_recovery')), findsOneWidget);
      await fields.tap(tester, 'booking_search_submit');
      await fields.reveal(tester, 'booking_open_${fixture.shop.workspaceId}');
      expect(tester.widget<OutlinedButton>(find.byKey(
        Key('booking_open_${fixture.shop.workspaceId}'))).onPressed, isNull);
      await fields.tap(tester, 'booking_recovery_resolve');
      expect(resolves, 1);
      expect(find.byKey(const Key('booking_pending_recovery')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('booking_recovery_outcome'))).data,
        contains(bookingStatusLabel(GarageBookingStatus.withdrawn)));
      expect(find.byKey(const Key('booking_sent_notice')), findsNothing);
      final action = tester.widget<OutlinedButton>(find.byKey(
        const Key('booking_recovery_history'))).onPressed!;
      action(); action();
      await tester.pumpAndSettle();
      expect(histories, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('definitively absent request allows a fresh form only after explicit action', (tester) async {
    var pending = [marker];
    await fixture.render(tester, GarageBookingSearchScreen(search: search,
      submit: neverSubmit, pendingRequests: () => pending,
      resolveRequest: (_) async { pending = []; return const BookingRecoveryOutcome(); }));
    await fields.tap(tester, 'booking_recovery_resolve');
    expect(find.text(GarageUiText.get('bookingRecoveryNotReceived')), findsOneWidget);
    expect(find.byType(GarageBookingRequestScreen), findsNothing);
    await fields.tap(tester, 'booking_search_submit');
    await fields.tap(tester, 'booking_open_${fixture.shop.workspaceId}');
    expect(find.byType(GarageBookingRequestScreen), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byKey(const Key('booking_name')))
      .controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed recovery remains blocked and repeated clicks make one RPC', (tester) async {
    final result = Completer<BookingRecoveryOutcome>();
    var calls = 0;
    await fixture.render(tester, GarageBookingSearchScreen(search: search,
      submit: neverSubmit, pendingRequests: () => [marker],
      resolveRequest: (_) { calls++; return result.future; }));
    await fields.tap(tester, 'booking_search_submit');
    await fields.reveal(tester, 'booking_recovery_resolve');
    final action = tester.widget<FilledButton>(find.byKey(
      const Key('booking_recovery_resolve'))).onPressed!;
    action(); action();
    await tester.pumpAndSettle();
    expect(calls, 1);
    result.completeError(TimeoutException('Synthetic recovery outage'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking_recovery_error')), findsOneWidget);
    await fields.reveal(tester, 'booking_open_${fixture.shop.workspaceId}');
    expect(tester.widget<OutlinedButton>(find.byKey(
      Key('booking_open_${fixture.shop.workspaceId}'))).onPressed, isNull);
    expect(find.byType(GarageBookingRequestScreen), findsNothing);
  });

  testWidgets('scope change discards late resolution and its history navigation', (tester) async {
    final result = Completer<BookingRecoveryOutcome>();
    late StateSetter replace;
    BookingPendingRead pending = () => [marker];
    BookingResolve resolve = (_) => result.future;
    var history = 0;
    await fixture.render(tester, StatefulBuilder(builder: (_, setState) {
      replace = setState;
      return GarageBookingSearchScreen(search: search, submit: neverSubmit,
        pendingRequests: pending, resolveRequest: resolve, onViewBookings: () => history++);
    }));
    await fields.tap(tester, 'booking_recovery_resolve');
    replace(() { pending = () => []; resolve = (_) async => const BookingRecoveryOutcome(); });
    await tester.pumpAndSettle();
    result.complete(const BookingRecoveryOutcome(bookingId: fixture.bookingId,
      status: GarageBookingStatus.confirmed));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking_recovery_outcome')), findsNothing);
    expect(find.byKey(const Key('booking_recovery_history')), findsNothing);
    expect(history, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restricted storage blocks opening a request and can be checked again', (tester) async {
    var blocked = true;
    await fixture.render(tester, GarageBookingSearchScreen(search: search,
      submit: neverSubmit, pendingRequests: () {
        if (blocked) throw StateError('Synthetic storage restriction');
        return [];
      }, resolveRequest: (_) async => const BookingRecoveryOutcome()));
    expect(find.byKey(const Key('booking_recovery_storage')), findsOneWidget);
    await fields.tap(tester, 'booking_search_submit');
    await fields.reveal(tester, 'booking_open_${fixture.shop.workspaceId}');
    expect(tester.widget<OutlinedButton>(find.byKey(
      Key('booking_open_${fixture.shop.workspaceId}'))).onPressed, isNull);
    blocked = false;
    await fields.tap(tester, 'booking_recovery_refresh');
    expect(find.byKey(const Key('booking_recovery_storage')), findsNothing);
    await fields.tap(tester, 'booking_open_${fixture.shop.workspaceId}');
    expect(find.byType(GarageBookingRequestScreen), findsOneWidget);
  });
}
