import 'dart:async';

import 'package:fleetpilot/core/app_config.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/billing_screen.dart';
import 'package:fleetpilot/garage/checkout_card.dart';
import 'package:fleetpilot/garage/checkout_repository.dart';
import 'package:fleetpilot/garage/checkout_text.dart';
import 'package:fleetpilot/garage/entitlement_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const qa = 'https://fyestmquqvkdebxxbcky.supabase.co';
  const production = 'https://wqhymmtiawfwjikdaujo.supabase.co';
  const actor = '00000000-0000-4000-8000-000000000001';
  const workspace = '00000000-0000-4000-8000-000000000002';
  const otherWorkspace = '00000000-0000-4000-8000-000000000003';
  const response = <String, Object>{'mode': 'test', 'session_id': 'cs_test_fixture',
    'url': 'https://checkout.stripe.com/c/pay/cs_test_fixture#synthetic', 'trial_days': 7};

  GarageCheckoutRepository repo({bool enabled = true, String url = qa,
      GarageCheckoutInvoke? invoke, String? Function()? user,
      String? Function()? session}) => GarageCheckoutRepository(
    enabled: enabled, supabaseUrl: url, currentUserId: user ?? () => actor,
    currentSessionKey: session ?? () => 'synthetic-session',
    invoke: invoke ?? (_) async => response);

  Widget page(GarageCheckoutRepository repository, {String scope = workspace,
      bool owner = true, GarageCheckoutLauncher? open, VoidCallback? refresh}) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      GarageSandboxCheckoutCard(repository: repository, workspaceId: scope,
        isOwner: owner, openCheckout: open, onRefreshStatus: refresh))));

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
  }
  Finder prepare() => find.widgetWithText(FilledButton, GarageCheckoutText.get(4));
  Finder openButton() => find.widgetWithText(FilledButton, GarageCheckoutText.get(5));
  Future<void> prepareReady(WidgetTester tester) async {
    await confirm(tester);
    await tester.ensureVisible(prepare());
    await tester.tap(prepare());
    await tester.pumpAndSettle();
  }

  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  test('UI requires independent request, client, entitlement and exact QA gates', () {
    bool enabled({String url = qa, bool requested = true,
        bool client = true, bool entitlement = true}) =>
      AppConfig.garageSandboxCheckoutUiEnabledFor(url, requested: requested,
        clientEnabled: client, entitlementEnabled: entitlement);
    expect(enabled(), isTrue);
    expect(enabled(requested: false), isFalse);
    expect(enabled(client: false), isFalse);
    expect(enabled(entitlement: false), isFalse);
    expect(enabled(url: production), isFalse);
    expect(enabled(url: '$qa/'), isFalse);
  });

  for (final language in supportedLanguages) {
    testWidgets('$language QA form fits a 320px phone and starts no requests', (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppLocale.language.value = language;
      var calls = 0;
      await tester.pumpWidget(page(repo(invoke: (_) async { calls++; return response; })));
      await tester.pumpAndSettle();
      expect(find.text(GarageCheckoutText.get(0)), findsOneWidget);
      expect(tester.widget<FilledButton>(prepare()).onPressed, isNull);
      expect(GarageCheckoutText.translations[language]?.length, 11);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('non-owner, signed-out, disabled and production views expose no controls', (tester) async {
    var calls = 0;
    Future<Object?> invoke(Map<String, Object> _) async { calls++; return response; }
    for (final widget in [
      page(repo(invoke: invoke), owner: false),
      page(repo(invoke: invoke, session: () => null)),
      page(repo(invoke: invoke, user: () => null)),
      page(repo(invoke: invoke, enabled: false)),
      page(repo(invoke: invoke, url: production)),
    ]) {
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
    }
    expect(calls, 0);
  });

  testWidgets('changing period clears business confirmation', (tester) async {
    await tester.pumpWidget(page(repo()));
    await confirm(tester);
    expect(tester.widget<FilledButton>(prepare()).onPressed, isNotNull);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yearly').last);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
    expect(tester.widget<FilledButton>(prepare()).onPressed, isNull);
  });

  testWidgets('preparation sends once, freezes controls and requires a separate open gesture', (tester) async {
    var calls = 0;
    var opened = 0;
    final pending = Completer<Object?>();
    final repository = repo(invoke: (body) {
      expect(body['workspace_id'], workspace);
      expect(body['billing_interval'], 'month');
      calls++; return pending.future;
    });
    await tester.pumpWidget(page(repository, open: (_) async { opened++; return true; }));
    await confirm(tester);
    await tester.ensureVisible(prepare());
    await tester.tap(prepare());
    await tester.tap(prepare());
    await tester.pump();
    expect(calls, 1);
    expect(opened, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).onChanged, isNull);
    pending.complete(response);
    await tester.pumpAndSettle();
    expect(openButton(), findsOneWidget);
    expect(opened, 0);
    await tester.ensureVisible(openButton());
    await tester.tap(openButton());
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(calls, 1);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text(GarageCheckoutText.get(8)), findsOneWidget);
  });

  for (final sameUser in [false, true]) {
    testWidgets('changing account/session after preparation prevents navigation ($sameUser)', (tester) async {
      var user = actor;
      var session = 'first-session';
      var opened = 0;
      final repository = repo(user: () => user, session: () => session);
      await tester.pumpWidget(page(repository, open: (_) async { opened++; return true; }));
      await prepareReady(tester);
      if (!sameUser) user = '00000000-0000-4000-8000-000000000004';
      session = 'replacement-session';
      await tester.ensureVisible(openButton());
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(find.text(GarageCheckoutText.get(7)), findsOneWidget);
      expect(openButton(), findsNothing);
    });
  }

  for (final owner in [false, true]) {
    testWidgets('scope/owner replacement discards pending old-workshop response ($owner)', (tester) async {
      var calls = 0;
      var opened = 0;
      final pending = Completer<Object?>();
      final repository = repo(invoke: (_) { calls++; return pending.future; });
      Future<bool> open(Uri _) async { opened++; return true; }
      await tester.pumpWidget(page(repository, open: open));
      await confirm(tester);
      await tester.ensureVisible(prepare());
      await tester.tap(prepare());
      await tester.pump();
      await tester.pumpWidget(page(repository, scope: otherWorkspace,
        owner: owner, open: open));
      pending.complete(response);
      await tester.pumpAndSettle();
      expect(openButton(), findsNothing);
      expect(prepare(), findsNothing);
      expect(calls, 1);
      expect(opened, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('removing page while request is pending produces no navigation or setState', (tester) async {
    final pending = Completer<Object?>();
    var opened = 0;
    await tester.pumpWidget(page(repo(invoke: (_) => pending.future),
      open: (_) async { opened++; return true; }));
    await confirm(tester);
    await tester.ensureVisible(prepare());
    await tester.tap(prepare());
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(response);
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(tester.takeException(), isNull);
  });

  for (final throwError in [false, true]) {
    testWidgets('failed navigation locks attempt without new Checkout ($throwError)', (tester) async {
      var calls = 0;
      final repository = repo(invoke: (_) async { calls++; return response; });
      await tester.pumpWidget(page(repository, open: (_) async {
        if (throwError) throw StateError('PRIVATE');
        return false;
      }));
      await prepareReady(tester);
      await tester.ensureVisible(openButton());
      await tester.tap(openButton());
      await tester.pumpAndSettle();
      expect(find.text(GarageCheckoutText.get(7)), findsOneWidget);
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(calls, 1);
    });
  }

  testWidgets('opaque preparation failure offers status check without retry or navigation', (tester) async {
    var calls = 0;
    var refreshes = 0;
    final repository = repo(invoke: (_) { calls++; throw StateError('PRIVATE'); });
    await tester.pumpWidget(page(repository, refresh: () { refreshes++; }));
    await prepareReady(tester);
    expect(find.text(GarageCheckoutText.get(7)), findsOneWidget);
    expect(find.textContaining('PRIVATE'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    await tester.ensureVisible(find.text(GarageCheckoutText.get(9)));
    await tester.tap(find.text(GarageCheckoutText.get(9)));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(calls, 1);
  });

  testWidgets('Checkout navigation never grants trial access; status refresh reads entitlement', (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(home: GarageBillingScreen(
      workshopName: 'QA Workshop', workspaceId: workspace, isOwner: true,
      checkoutRepository: repo(), openCheckout: (_) async => true,
      loadEntitlement: () async {
        reads++;
        return GarageEntitlementRead.verified(const GarageEntitlement(active: false), trialAvailable: true);
      })));
    await tester.pumpAndSettle();
    await prepareReady(tester);
    await tester.ensureVisible(openButton());
    await tester.tap(openButton());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(GarageCheckoutText.get(9)));
    await tester.tap(find.text(GarageCheckoutText.get(9)));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('No current trial or paid access'), findsOneWidget);
    expect(find.textContaining('Trial access confirmed'), findsNothing);
  });
}
