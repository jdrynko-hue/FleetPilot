import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/mechanic_board.dart';
import 'package:fleetpilot/garage/mechanic_work_screen.dart';
import 'package:fleetpilot/garage/work_order_domain.dart';

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  const jobs = <GarageMechanicAssignment>[
    GarageMechanicAssignment(
      id: 'work-1',
      registration: 'FJ70 VDF',
      make: 'Mercedes',
      model: 'Sprinter',
      complaint: 'Brake inspection',
      status: GarageOrderStatus.diagnosing,
    ),
  ];

  Future<void> render(
    WidgetTester tester, {
    required double width,
    required GarageJobsLoader loadJobs,
    GarageEvidenceBuilder? evidenceScreen,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: GarageMechanicWorkScreen(
        loadJobs: loadJobs,
        evidenceScreen: evidenceScreen ??
            (orderId) => Scaffold(
              appBar: AppBar(title: const Text('Repair evidence')),
              body: Text('Private evidence for $orderId'),
            ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 375.0, 390.0, 900.0]) {
    testWidgets('assigned mechanic sees only supplied jobs on width $width',
        (tester) async {
      await render(tester, width: width, loadJobs: () async => jobs);
      expect(find.text('Flotaryx Garage'), findsOneWidget);
      expect(find.text('FJ70 VDF'), findsOneWidget);
      expect(find.text('Total: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selecting an assignment routes to its private evidence',
      (tester) async {
    var loads = 0;
    await render(
      tester,
      width: 390,
      loadJobs: () async {
        loads++;
        return jobs;
      },
    );
    await tester.tap(find.byKey(const Key('garage_mechanic_job_work-1')));
    await tester.pumpAndSettle();
    expect(find.text('Private evidence for work-1'), findsOneWidget);
    expect(loads, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(loads, 2, reason: 'Returning refetches RLS-scoped assignments');
    expect(find.text('FJ70 VDF'), findsOneWidget);
  });

  testWidgets('returning after reassignment removes old job from UI',
      (tester) async {
    var assigned = true;
    await render(tester, width: 390,
      loadJobs: () async => assigned ? jobs : const [],
    );
    await tester.tap(find.byKey(const Key('garage_mechanic_job_work-1')));
    await tester.pumpAndSettle();
    assigned = false; // Server no longer returns the transferred work order.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('FJ70 VDF'), findsNothing);
    expect(find.byKey(const Key('garage_mechanic_empty')), findsOneWidget);
  });

  testWidgets('loading failure shows no stale vehicle information',
      (tester) async {
    var shouldFail = false;
    await render(tester, width: 375,
      loadJobs: () async {
        if (shouldFail) throw StateError('Access revoked');
        return jobs;
      },
    );
    expect(find.text('FJ70 VDF'), findsOneWidget);
    shouldFail = true;
    await tester.tap(find.byKey(const Key('garage_mechanic_work_refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('garage_mechanic_work_error')), findsOneWidget);
    expect(find.text('FJ70 VDF'), findsNothing);
    expect(find.byKey(const Key('garage_mechanic_job_work-1')), findsNothing);
  });

  testWidgets('failed load can be retried without revealing other jobs',
      (tester) async {
    var fails = true;
    await render(tester, width: 320,
      loadJobs: () async {
        if (fails) throw StateError('Temporary failure');
        return const [];
      },
    );
    expect(find.byKey(const Key('garage_mechanic_work_error')), findsOneWidget);
    fails = false;
    await tester.tap(find.byKey(const Key('garage_mechanic_work_retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('garage_mechanic_empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PL labels are used for errors and assigned jobs',
      (tester) async {
    AppLocale.language.value = 'pl';
    await render(tester, width: 375, loadJobs: () async => jobs);
    expect(find.text('Moje zlecenia'), findsOneWidget);
    expect(find.text('Razem: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
