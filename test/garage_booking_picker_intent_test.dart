import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';

import 'garage_booking_screens_test.dart' as fixture;

Future<String> noSubmit({required String workspaceId, required String customerName,
    required String vehicleMake, required String vehicleModel,
    required String service, required String concern,
    required DateTime desiredStart, required String requestKey,
    String? registration}) async => throw StateError('Unexpected submission');

Future<VoidCallback> pickerAction(WidgetTester tester) async {
  final picker = find.byKey(const Key('booking_pick_time'));
  await tester.ensureVisible(picker);
  await tester.pumpAndSettle();
  return tester.widget<OutlinedButton>(picker).onPressed!;
}

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  for (final outcome in ['selected', 'cancelled', 'throws']) {
    testWidgets('one date selection intent unlocks after $outcome', (tester) async {
      final pending = Completer<DateTime?>();
      var picks = 0;
      await fixture.render(tester, GarageBookingRequestScreen(
        shop: fixture.shop, submit: noSubmit,
        pickTime: (_) { picks++; return picks == 1 ? pending.future : Future.value(null); },
      ));
      final pick = await pickerAction(tester);
      pick(); pick(); pick();
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('booking_pick_time'))).onPressed, isNull);
      expect(tester.widget<FilledButton>(find.byKey(const Key('booking_send'))).onPressed, isNull);
      if (outcome == 'throws') {
        pending.completeError(StateError('Private picker detail'));
      } else {
        pending.complete(outcome == 'selected' ? DateTime.now().add(const Duration(days: 2)) : null);
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('Private picker detail'), findsNothing);
      expect(find.byKey(const Key('booking_request_error')),
        outcome == 'throws' ? findsOneWidget : findsNothing);
      if (outcome == 'throws') {
        expect(find.text(GarageUiText.get('bookingInvalidLocalTime')), findsOneWidget);
      }
      final retry = await pickerAction(tester);
      retry();
      await tester.pumpAndSettle();
      expect(picks, 2);
      expect(find.text(GarageUiText.get('bookingPickTime')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final oldFails in [false, true]) {
    testWidgets('old date picker cannot unlock replacement scope error=$oldFails',
        (tester) async {
      final old = Completer<DateTime?>();
      final current = Completer<DateTime?>();
      await fixture.render(tester, GarageBookingRequestScreen(
        shop: fixture.shop, submit: noSubmit, pickTime: (_) => old.future,
      ));
      (await pickerAction(tester))();
      await tester.pumpAndSettle();
      await fixture.render(tester, GarageBookingRequestScreen(
        shop: fixture.shop, submit: noSubmit, pickTime: (_) => current.future,
      ));
      (await pickerAction(tester))();
      await tester.pumpAndSettle();
      if (oldFails) {
        old.completeError(StateError('Private old picker detail'));
      } else {
        old.complete(DateTime.now().add(const Duration(days: 3)));
      }
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('booking_pick_time'))).onPressed, isNull);
      expect(tester.widget<FilledButton>(find.byKey(const Key('booking_send'))).onPressed, isNull);
      expect(find.byKey(const Key('booking_request_error')), findsNothing);
      current.complete(DateTime.now().add(const Duration(days: 2)));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('booking_pick_time'))).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late picker failure after disposal is ignored', (tester) async {
    final pending = Completer<DateTime?>();
    await fixture.render(tester, GarageBookingRequestScreen(
      shop: fixture.shop, submit: noSubmit, pickTime: (_) => pending.future,
    ));
    (await pickerAction(tester))();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: Text('Signed out')));
    pending.completeError(StateError('Private disposed picker detail'));
    await tester.pumpAndSettle();
    expect(find.text('Signed out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
