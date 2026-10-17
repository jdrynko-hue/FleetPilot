import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/auth/portal_entry.dart';
import 'package:fleetpilot/ecosystem/customer_portal.dart';

void main() {
  test('search URL is customer intent, never Fleet', () {
    expect(portalEntryFromUri(Uri.parse('https://example.test/app/?portal=search')), PortalEntry.customer);
  });
  for (final first in [false, true]) {
    testWidgets('customer tabs build only the selected page, searchFirst=$first', (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final builds = [0, 0, 0];
      await tester.pumpWidget(MaterialApp(home: CustomerPortal(searchFirst: first,
        pages: List.generate(3, (index) => (_) {
          builds[index]++;
          return Scaffold(body: Text('Page $index'));
        }))));
      expect(find.text('Page ${first ? 0 : 1}'), findsOneWidget);
      expect(builds[2], 0);
      expect(builds[first ? 1 : 0], 0);
      await tester.tap(find.byKey(const Key('customer_notifications_tab')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('customer_search_tab')));
      await tester.pumpAndSettle();
      expect(find.text('Page 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
