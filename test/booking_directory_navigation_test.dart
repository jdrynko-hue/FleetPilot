import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';

const shop = GarageBookingWorkshop(workspaceId: '00000000-0000-4000-8000-000000000001',
  name: 'Test workshop', city: 'Luton', country: 'GB', timeZone: 'Europe/London', services: ['brakes']);

Future<void> openDirectory(WidgetTester tester, {Future<bool> Function()? beforeRequest}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: GarageBookingSearchScreen(
    search: ({city}) async => [shop], beforeRequest: beforeRequest,
    submit: ({required workspaceId, required customerName, required vehicleMake,
      required vehicleModel, required service, required concern, required desiredStart,
      required requestKey, registration}) async => throw StateError('Must not submit'))));
  await tester.tap(find.byKey(const Key('booking_search_submit')));
  await tester.pumpAndSettle();
}

Finder get requestButton => find.byKey(Key('booking_open_${shop.workspaceId}'));

void main() {
  testWidgets('rapid taps open only one request and returning permits another', (tester) async {
    await openDirectory(tester);
    final action = tester.widget<OutlinedButton>(requestButton).onPressed!;
    action(); action();
    await tester.pumpAndSettle();
    expect(find.byType(GarageBookingRequestScreen, skipOffstage: false), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(requestButton).onPressed, isNotNull);
    await tester.tap(requestButton);
    await tester.pumpAndSettle();
    expect(find.byType(GarageBookingRequestScreen, skipOffstage: false), findsOneWidget);
  });
  testWidgets('pending and completed login handoff cannot run twice', (tester) async {
    final decision = Completer<bool>();
    var calls = 0;
    await openDirectory(tester, beforeRequest: () { calls++; return decision.future; });
    final action = tester.widget<OutlinedButton>(requestButton).onPressed!;
    action(); action();
    expect(calls, 1);
    decision.complete(false);
    await tester.pumpAndSettle();
    action();
    expect(calls, 1);
    expect(find.byType(GarageBookingRequestScreen), findsNothing);
  });
  testWidgets('failed handoff shows a safe error and allows retry', (tester) async {
    await openDirectory(tester, beforeRequest: () async => throw StateError('PRIVATE DETAIL'));
    await tester.tap(requestButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking_search_error')), findsOneWidget);
    expect(find.textContaining('PRIVATE DETAIL'), findsNothing);
    expect(tester.widget<OutlinedButton>(requestButton).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
