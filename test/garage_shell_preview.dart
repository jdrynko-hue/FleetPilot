// Render real Garage widgets for review; run explicitly with --update-goldens.
// No backend, account, session, invented metrics or customer records are used.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/core/theme.dart';
import 'package:fleetpilot/garage/garage_shell.dart';
import 'package:fleetpilot/garage/setup_guide.dart';
import 'package:fleetpilot/garage/booking_recovery_journal.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT']!;
    final loader = FontLoader('Roboto');
    loader.addFont(File('$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
      .readAsBytes().then((b) => ByteData.sublistView(b)));
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
      .readAsBytes().then((b) => ByteData.sublistView(b)));
    await icons.load();
  });
  for (final size in [const Size(390, 844), const Size(1200, 900)]) {
    testWidgets('render Polish Garage at ${size.width.toInt()}px', (tester) async {
      AppLocale.language.value = 'pl';
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: buildFleetPilotTheme(), home:
        GarageShell(scopeId: 'visual-review', workshopName: 'Twój warsztat', pages: [
          (context) => GarageHome(workshopName: 'Twój warsztat',
            onCalendar: () => GarageShell.selectTab(context, 1),
            onOrders: () => GarageShell.selectTab(context, 2),
            onRequests: () => GarageShell.selectTab(context, 3),
            onFleetRequests: () {},
            setupGuide: GarageSetupGuide(openProfile: () {}, openCalendar: () {}, openRequests: () {})),
          for (var i=1;i<5;i++) (_) => const SizedBox.shrink(),
        ])));
      await tester.runAsync(() => precacheImage(
        const AssetImage('assets/branding/flotaryx_mark.png'),
        tester.element(find.byType(GarageShell))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(GarageShell), matchesGoldenFile(
        '../build/garage-preview/garage_pl_${size.width.toInt()}.png'));
    });
  }
  for (final resolved in [false, true]) {
    testWidgets('render Polish Booking recovery, resolved=$resolved', (tester) async {
      AppLocale.language.value = 'pl';
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var pending = true;
      final marker = PendingBookingRequest(
        actorId: '00000000-0000-4000-8000-000000000001',
        workspaceId: '00000000-0000-4000-8000-000000000101',
        requestKey: '00000000-0000-4000-8000-000000000201', createdAt: DateTime.utc(2026));
      await tester.pumpWidget(MaterialApp(theme: buildFleetPilotTheme(), home:
        GarageBookingSearchScreen(search: ({city}) async => [],
          submit: ({required workspaceId, required customerName, required vehicleMake,
            required vehicleModel, required service, required concern,
            required desiredStart, required requestKey, registration}) async =>
              throw StateError('Visual review cannot submit a request'),
          pendingRequests: () => pending ? [marker] : [],
          resolveRequest: (_) async {
            pending = false;
            return const BookingRecoveryOutcome(
              bookingId: '00000000-0000-4000-8000-000000000301',
              status: GarageBookingStatus.withdrawn);
          }, onViewBookings: () {})));
      await tester.pumpAndSettle();
      if (resolved) {
        await tester.tap(find.byKey(const Key('booking_recovery_resolve')));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(GarageBookingSearchScreen), matchesGoldenFile(
        '../build/garage-preview/booking_recovery_pl_${resolved ? 'resolved' : 'pending'}_390.png'));
    });
  }
}
