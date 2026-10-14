import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/mechanic_board.dart';
import 'package:fleetpilot/garage/work_order_domain.dart';

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  const assigned = [
    GarageMechanicAssignment(
      id: 'work-1',
      registration: 'FJ70 VDF',
      make: 'Mercedes-Benz',
      model: 'Sprinter',
      complaint: 'Driver reported brake noise and vibration on approach.',
      status: GarageOrderStatus.inProgress,
    ),
    GarageMechanicAssignment(
      id: 'work-2',
      registration: 'AB123456789012345678901234567890',
      make: 'Very Long Manufacturer Name',
      model: 'Very Long Model Name Which Must Be Truncated',
      complaint: 'Customer requests detailed inspection of many components.',
      status: GarageOrderStatus.awaitingParts,
    ),
  ];

  Future<void> loadBoard(
    WidgetTester tester, {
    required double width,
    required List<GarageMechanicAssignment> jobs,
    ValueChanged<String>? onOpen,
  }) async {
    tester.view.physicalSize = Size(width, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GarageMechanicBoard(
            assignments: jobs,
            onOpenAssignment: onOpen ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 375.0, 390.0, 900.0]) {
    testWidgets('mechanic board fits ${width}px without long label overflow',
        (tester) async {
      await loadBoard(tester, width: width, jobs: assigned);
      expect(find.byKey(const Key('garage_mechanic_jobs')), findsOneWidget);
      expect(find.byKey(const Key('garage_mechanic_job_work-1')),
          findsOneWidget);
      expect(find.text('Total: 2'), findsOneWidget);
      expect(find.text('In progress: 1'), findsOneWidget);
      expect(find.text('Awaiting parts: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty assignments show a safe empty state', (tester) async {
    await loadBoard(tester, width: 320, jobs: const []);
    expect(find.byKey(const Key('garage_mechanic_empty')), findsOneWidget);
    expect(find.byKey(const Key('garage_mechanic_jobs')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('job selection passes only the selected job ID', (tester) async {
    String? opened;
    await loadBoard(
      tester,
      width: 390,
      jobs: assigned,
      onOpen: (id) => opened = id,
    );
    await tester.tap(find.byKey(const Key('garage_mechanic_job_work-1')));
    await tester.pumpAndSettle();
    expect(opened, 'work-1');
  });

  testWidgets('board renders exactly supplied assignments, no hidden data',
      (tester) async {
    await loadBoard(tester, width: 390, jobs: [assigned.first]);
    expect(find.text('FJ70 VDF'), findsOneWidget);
    expect(find.text('AB123456789012345678901234567890'), findsNothing);
    expect(find.text('Total: 1'), findsOneWidget);
  });

  testWidgets('Polish labels show status and assigned-only explanation',
      (tester) async {
    AppLocale.language.value = 'pl';
    await loadBoard(tester, width: 375, jobs: [assigned.first]);
    expect(find.text('Moje zlecenia'), findsOneWidget);
    expect(find.text('Tylko zlecenia przydzielone do Twojego konta.'),
        findsOneWidget);
    expect(find.text('W trakcie'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
