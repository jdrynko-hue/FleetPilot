import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/data/models.dart';
import 'package:fleetpilot/shell/fleet_app_bar.dart';

void main() {
  setUp(() => AppLocale.language.value = 'en');

  final primary = CompanyMembership(
    companyId: 'fleet-1',
    companyName: 'A very long transport company name for mobile layouts',
    role: 'owner',
    currency: 'GBP',
  );
  final secondary = CompanyMembership(
    companyId: 'fleet-2',
    companyName: 'Second fleet',
    role: 'manager',
    currency: 'GBP',
  );

  Future<void> showHeader(
    WidgetTester tester, {
    required double width,
    required List<CompanyMembership> memberships,
    bool compact = true,
    bool canManage = true,
    VoidCallback? onRefresh,
    VoidCallback? onSignOut,
    VoidCallback? onManager,
    ValueChanged<String>? onSelectFleet,
    Widget businessReviewAlert = const SizedBox.shrink(),
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: FleetAppBar(
            memberships: memberships,
            selectedMembership: primary,
            compact: compact,
            canManage: canManage,
            businessReviewAlert: businessReviewAlert,
            onFleetSelected: onSelectFleet ?? (_) {},
            onManagerPressed: onManager ?? () {},
            onNotificationsPressed: () {},
            onRefreshPressed: onRefresh ?? () {},
            onSignOutPressed: onSignOut ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 375.0, 390.0]) {
    testWidgets('phone toolbar fits width $width with long company name',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showHeader(tester, width: width, memberships: [primary]);
      expect(find.byKey(const Key('fleet_company_name')), findsOneWidget);
      expect(find.byKey(const Key('fleet_notifications')), findsOneWidget);
      expect(find.byKey(const Key('fleet_mobile_menu')), findsOneWidget);
      expect(tester.takeException(), isNull);
      final menu = tester.getRect(find.byKey(const Key('fleet_mobile_menu')));
      expect(menu.right, lessThanOrEqualTo(width));
      expect(menu.left, greaterThanOrEqualTo(0));
    });
  }

  testWidgets('operator action does not push mobile menu offscreen',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showHeader(
      tester,
      width: 320,
      memberships: [primary],
      businessReviewAlert: IconButton(
        icon: const Icon(Icons.fact_check_outlined),
        onPressed: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byKey(const Key('fleet_mobile_menu'))).right,
        lessThanOrEqualTo(320));
  });

  testWidgets('mobile menu retains manager, refresh and sign-out actions',
      (tester) async {
    var refreshed = 0;
    var signedOut = 0;
    var managed = 0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showHeader(
      tester,
      width: 390,
      memberships: [primary],
      onRefresh: () => refreshed++,
      onSignOut: () => signedOut++,
      onManager: () => managed++,
    );

    await tester.tap(find.byKey(const Key('fleet_mobile_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fleet_menu_manager')));
    await tester.pumpAndSettle();
    expect(managed, 1);

    await tester.tap(find.byKey(const Key('fleet_mobile_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fleet_menu_refresh')));
    await tester.pumpAndSettle();
    expect(refreshed, 1);

    await tester.tap(find.byKey(const Key('fleet_mobile_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fleet_menu_signout')));
    await tester.pumpAndSettle();
    expect(signedOut, 1);
  });

  testWidgets('fleet selection is available on narrow phones',
      (tester) async {
    String? selected;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showHeader(
      tester,
      width: 320,
      memberships: [primary, secondary],
      onSelectFleet: (companyId) => selected = companyId,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('fleet_company_selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second fleet').last);
    await tester.pumpAndSettle();
    expect(selected, 'fleet-2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop toolbar keeps direct actions', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showHeader(
      tester,
      width: 1000,
      memberships: [primary],
      compact: false,
    );
    expect(find.byKey(const Key('fleet_mobile_menu')), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
