import 'dart:async';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/create_workspace_screen.dart';
import 'package:fleetpilot/garage/garage_ui_text.dart';
import 'package:fleetpilot/ecosystem/ecosystem_gate.dart';
import 'package:fleetpilot/ecosystem/ecosystem_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');
  Future<void> ready(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('garage_create_name')), '  New workshop  ');
    final business = find.byKey(const Key('garage_create_business'));
    await tester.ensureVisible(business); await tester.pumpAndSettle();
    await tester.tap(business); await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('garage_create_submit')));
    await tester.pumpAndSettle();
  }
  testWidgets('module chooser opens workshop registration and reloads on return', (tester) async {
    var loads = 0;
    await tester.pumpWidget(MaterialApp(home: EcosystemGate(
      loadAccess: () async { loads++; return const EcosystemAccess(hasFleet: false, garages: []); },
      destinationBuilder: (_) => const Scaffold(body: Text('Customer destination')),
      signOut: () async {}, isCurrentAccount: () => true,
      createWorkshopBuilder: (routeContext) => Scaffold(body: FilledButton(
        key: const Key('finish_registration'),
        onPressed: () => Navigator.of(routeContext).pop(), child: const Text('Finish'))),
    )));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(find.byKey(const Key('ecosystem_customer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ecosystem_create_workshop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('finish_registration')), findsOneWidget);
    await tester.tap(find.byKey(const Key('finish_registration')));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.byKey(const Key('ecosystem_customer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creation requires name and business confirmation then sends one request', (tester) async {
    final pending = Completer<void>();
    var requests = 0;
    var created = 0;
    await tester.pumpWidget(MaterialApp(home: GarageCreateWorkspaceScreen(
      isCurrentAccount: () => true, onCreated: () => created++,
      create: ({required name, required country}) {
        expect(name, 'New workshop'); expect(country, 'GB');
        requests++; return pending.future;
      })));
    expect(tester.widget<FilledButton>(find.byKey(const Key('garage_create_submit'))).onPressed, isNull);
    await ready(tester);
    await tester.tap(find.byKey(const Key('garage_create_submit'))); await tester.pump();
    expect(requests, 1);
    expect(tester.widget<FilledButton>(find.byKey(const Key('garage_create_submit'))).onPressed, isNull);
    pending.complete(); await tester.pumpAndSettle(); expect(created, 1);
  });
  testWidgets('uncertain creation blocks repeat submit without exposing error detail', (tester) async {
    var requests = 0;
    await tester.pumpWidget(MaterialApp(home: GarageCreateWorkspaceScreen(
      isCurrentAccount: () => true, onCreated: () => fail('Unexpected completion'),
      create: ({required name, required country}) async {
        requests++; throw StateError('PRIVATE DETAIL');
      })));
    await ready(tester);
    await tester.tap(find.byKey(const Key('garage_create_submit'))); await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.byKey(const Key('garage_create_uncertain')), findsOneWidget);
    expect(find.textContaining('PRIVATE DETAIL'), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('garage_create_submit'))).onPressed, isNull);
  });
  for (final transition in ['account', 'disposed']) {
    testWidgets('late creation response cannot navigate after $transition change', (tester) async {
      final pending = Completer<void>();
      var current = true;
      var created = 0;
      await tester.pumpWidget(MaterialApp(home: GarageCreateWorkspaceScreen(
        isCurrentAccount: () => current, onCreated: () => created++,
        create: ({required name, required country}) => pending.future)));
      await ready(tester);
      await tester.tap(find.byKey(const Key('garage_create_submit'))); await tester.pump();
      if (transition == 'account') { current = false; }
      else { await tester.pumpWidget(const MaterialApp(home: SizedBox())); }
      pending.complete(); await tester.pumpAndSettle();
      expect(created, 0); expect(tester.takeException(), isNull);
    });
  }
  for (final locale in GarageUiText.labels.keys) {
    testWidgets('workshop form fits a narrow phone in $locale', (tester) async {
      AppLocale.language.value = locale;
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: GarageCreateWorkspaceScreen(
        isCurrentAccount: () => true, onCreated: () {},
        create: ({required name, required country}) async {})));
      await tester.pumpAndSettle();
      expect(find.text(GarageUiText.get('createWorkshop')), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
