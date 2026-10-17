import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'package:fleetpilot/garage/mechanic_board.dart';
import 'package:fleetpilot/garage/mechanic_work_screen.dart';
import 'package:fleetpilot/garage/work_order_domain.dart';

Future<void> mount(WidgetTester tester, GarageMechanicWorkScreen screen) async {
  tester.view.physicalSize = const Size(320, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final previousFatal = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previousFatal);
  });
  tearDown(() => AppLocale.language.value = 'en');

  final jobs = GarageOrderStatus.values.map((status) => GarageMechanicAssignment(
    id: status.name, registration: 'QA-${status.name}',
    make: 'Long Manufacturer Name', model: 'Long Model Name',
    complaint: 'Synthetic assigned work order with a long description for layout.',
    status: status,
  )).toList();

  for (final locale in supportedLanguages) {
    testWidgets('mechanic $locale localizes counters and every status at 320px',
        (tester) async {
      AppLocale.language.value = locale;
      final opened = <String>[];
      await mount(tester, GarageMechanicWorkScreen(
        loadJobs: () async => jobs,
        evidenceScreen: (id) {
          opened.add(id);
          return Scaffold(appBar: AppBar(), body: const Text('Synthetic evidence'));
        },
      ));
      expect(find.text(GarageUiText.get('myAssignedJobs')), findsOneWidget);
      expect(find.text(GarageUiText.get('mechanicAssignedOnly')), findsOneWidget);
      for (final entry in {
        'mechanicTotal': jobs.length,
        'mechanicInProgress': 1,
        'mechanicAwaitingParts': 1,
      }.entries) {
        final label = GarageUiText.format(entry.key, {'count': entry.value});
        expect(label, isNot(contains('{count}')));
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byTooltip(GarageUiText.get('refresh')), findsOneWidget);
      for (final status in GarageOrderStatus.values) {
        final card = find.byKey(Key('garage_mechanic_job_${status.name}'));
        await tester.scrollUntilVisible(card, 220);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        final key = status == GarageOrderStatus.ready ? 'readyCollection' : status.name;
        expect(find.descendant(of: card,
          matching: find.text(GarageUiText.get(key))), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('garage_mechanic_job_cancelled')));
      await tester.pumpAndSettle();
      expect(opened, isNotEmpty);
      expect(opened.toSet(), {'cancelled'});
      expect(find.text('Synthetic evidence'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mechanic $locale localizes load failure, retry and empty state',
        (tester) async {
      AppLocale.language.value = locale;
      var calls = 0;
      await mount(tester, GarageMechanicWorkScreen(
        loadJobs: () async {
          if (calls++ == 0) throw StateError('private backend detail');
          return [];
        },
        evidenceScreen: (_) => const SizedBox.shrink(),
      ));
      expect(find.text(GarageUiText.get('mechanicLoadFailed')), findsOneWidget);
      expect(find.textContaining('private backend detail'), findsNothing);
      expect(find.text(GarageUiText.get('retry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('garage_mechanic_work_retry')));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text(GarageUiText.get('mechanicNoJobs')), findsOneWidget);
      expect(find.byKey(const Key('garage_mechanic_work_error')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
