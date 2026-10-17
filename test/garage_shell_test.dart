import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/core/theme.dart';
import 'package:fleetpilot/garage/garage_shell.dart';
import 'package:fleetpilot/garage/garage_shell_text.dart';

void main() {
  Widget app(Widget child) => MaterialApp(theme: buildFleetPilotTheme(), home: child);
  tearDown(() => AppLocale.language.value = 'en');
  testWidgets('workshop tabs load lazily and retain a visited draft', (tester) async {
    final visits = <int>[];
    await tester.pumpWidget(app(GarageShell(scopeId: 'A:owner', workshopName: 'Workshop A',
      pages: [for (var i=0;i<5;i++) (_) {
        visits.add(i);
        return Scaffold(body: TextField(key: Key('draft_$i')));
      }])));
    await tester.pumpAndSettle();
    expect(visits, [0]);
    await tester.tap(find.byKey(const Key('garage_tab_2')));
    await tester.pumpAndSettle();
    expect(visits, [0, 2]);
    await tester.enterText(find.byKey(const Key('draft_2')), 'Keep this draft');
    await tester.tap(find.byKey(const Key('garage_tab_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_tab_2')));
    await tester.pumpAndSettle();
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(visits.where((i) => i==2).length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('workspace or role changes discard private tab state', (tester) async {
    Widget shell(String scope) => app(GarageShell(scopeId: scope, workshopName: scope,
      pages: [for (var i=0;i<5;i++) (_) => Scaffold(body: TextField(key: Key('field_$i')))]));
    await tester.pumpWidget(shell('A:owner'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_tab_2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field_2')), 'Private old draft');
    await tester.pumpWidget(shell('B:owner'));
    await tester.pumpAndSettle();
    expect(find.text('Private old draft', skipOffstage: false), findsNothing);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
    await tester.tap(find.byKey(const Key('garage_tab_2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field_2')), 'Owner-only draft');
    await tester.pumpWidget(shell('B:adviser'));
    await tester.pumpAndSettle();
    expect(find.text('Owner-only draft', skipOffstage: false), findsNothing);
  });
  for (final language in supportedLanguages) {
    for (final width in [320.0, 1200.0]) {
      testWidgets('$language Garage layout fits ${width.toInt()}px', (tester) async {
        AppLocale.language.value = language;
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var opened = 0;
        await tester.pumpWidget(app(GarageShell(scopeId: 'A:owner',
          workshopName: 'A very long workshop name that must stay inside the header', pages: [
            (context) => GarageHome(workshopName: 'Workshop A',
              onCalendar: () { opened++; GarageShell.selectTab(context, 1); },
              onOrders: () {}, onRequests: () {}, onFleetRequests: () {}),
            for (var i=1;i<5;i++) (_) => Center(child: Text('Page $i')),
          ])));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationRail), width >= 900 ? findsOneWidget : findsNothing);
        expect(find.byType(NavigationBar), width < 900 ? findsOneWidget : findsNothing);
        await tester.tap(find.byKey(const Key('garage_home_calendarBays')));
        await tester.pumpAndSettle();
        expect(opened, 1);
        expect(find.text('Page 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('visited tabs with floating actions do not conflict on route push', (tester) async {
    await tester.pumpWidget(app(GarageShell(scopeId: 'A', workshopName: 'A', pages: [
      for (var i=0;i<5;i++) (context) => Scaffold(
        floatingActionButton: FloatingActionButton(onPressed: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Details')))),
          child: const Icon(Icons.add))),
    ])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_tab_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('short navigation labels cover every supported language', () {
    expect(GarageShellText.translations.keys.toSet(), supportedLanguages.toSet());
    for (final copy in GarageShellText.translations.values) {
      expect(copy.length, 3);
      expect(copy.every((text) => text.trim().isNotEmpty), isTrue);
    }
  });
}
