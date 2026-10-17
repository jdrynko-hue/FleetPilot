import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/mechanic_board.dart';
import 'package:fleetpilot/garage/mechanic_work_screen.dart';
import 'package:fleetpilot/garage/work_order_domain.dart';

const _jobs = [GarageMechanicAssignment(
  id: 'same-order', registration: 'QA VAN', make: 'Test', model: 'Van',
  complaint: 'Synthetic inspection', status: GarageOrderStatus.diagnosing,
)];

void main() {
  setUp(() {
    AppLocale.language.value = 'en';
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() {
    AppLocale.language.value = 'en';
    WidgetController.hitTestWarningShouldBeFatal = false;
  });

  testWidgets('rapid assignment activation opens one route and refreshes once',
      (tester) async {
    var loads = 0;
    await tester.pumpWidget(MaterialApp(home: GarageMechanicWorkScreen(
      loadJobs: () async { loads++; return _jobs; },
      evidenceScreen: (_) => Scaffold(
        appBar: AppBar(title: const Text('Evidence')),
      ),
    )));
    await tester.pumpAndSettle();
    final open = tester.widget<GarageMechanicBoard>(
      find.byType(GarageMechanicBoard)).onOpenAssignment;
    open('same-order');
    open('same-order');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Evidence'), findsNothing);
    expect(loads, 2);
  });

  for (final unrelatedDialog in [false, true]) {
    testWidgets('scope change removes only owned evidence dialog=$unrelatedDialog',
        (tester) async {
      final scope = ValueNotifier(0);
      addTearDown(scope.dispose);
      final navigator = GlobalKey<NavigatorState>();
      final loads = [0, 0];
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: ValueListenableBuilder<int>(
          valueListenable: scope,
          builder: (_, value, __) => GarageMechanicWorkScreen(
            loadJobs: () async { loads[value]++; return _jobs; },
            evidenceScreen: (_) => Scaffold(
              appBar: AppBar(title: Text('Private evidence $value')),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final staleOpen = tester.widget<GarageMechanicBoard>(
        find.byType(GarageMechanicBoard)).onOpenAssignment;
      await tester.tap(find.byKey(const Key('garage_mechanic_job_same-order')));
      await tester.pumpAndSettle();
      expect(find.text('Private evidence 0'), findsOneWidget);
      if (unrelatedDialog) {
        showDialog<void>(context: navigator.currentContext!,
          builder: (_) => const AlertDialog(content: Text('Unrelated dialog')));
        await tester.pumpAndSettle();
      }
      scope.value = 1;
      await tester.pumpAndSettle();
      expect(find.text('Private evidence 0', skipOffstage: false), findsNothing);
      expect(loads, [1, 1], reason: 'Old route return must not reload new scope');
      if (unrelatedDialog) {
        expect(find.text('Unrelated dialog'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
      }
      staleOpen('same-order');
      await tester.pumpAndSettle();
      expect(find.text('Private evidence 1'), findsNothing);
      await tester.tap(find.byKey(const Key('garage_mechanic_job_same-order')));
      await tester.pumpAndSettle();
      expect(find.text('Private evidence 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
