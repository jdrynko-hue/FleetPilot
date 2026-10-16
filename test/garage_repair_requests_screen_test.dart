import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/repair_bridge_repository.dart';
import 'package:fleetpilot/garage/repair_requests_screen.dart';

const shop = '00000000-0000-4000-8000-000000000001';
const other = '00000000-0000-4000-8000-000000000002';
Map<String, Object?> row(String id, String workspace) => {
  'request_id': id, 'company_id': other, 'workspace_id': workspace,
  'issue_title': 'Brakes', 'request_status': 'sent',
};
void main() {
  test('inbox excludes other workshops and rejects malformed responses', () {
    expect(GarageRepairRequest.parseList([row(shop, shop), row(other, other)], shop)
      .map((r) => r.id), [shop]);
    expect(() => GarageRepairRequest.parseList([row(shop, shop), row(shop, shop)], shop),
      throwsFormatException);
    expect(() => GarageRepairRequest.parseList([
      {...row(shop, shop), 'request_status': 'unknown'}], shop), throwsFormatException);
  });
  test('Fleet inbox is scoped by company independently of workshop', () {
    final rows = GarageRepairRequest.parseList([
      row(shop, shop), {...row(other, other), 'company_id': shop},
    ], other, fleet: true);
    expect(rows.map((r) => r.id), [shop]);
  });
  testWidgets('failure clears data and offers retry without exposing server error', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestsScreen(load: () async {
      if (++calls == 1) throw StateError('private server data');
      return const [GarageRepairRequest(shop, other, shop, 'Brakes', 'sent')];
    })));
    await tester.pumpAndSettle();
    expect(find.textContaining('private server data'), findsNothing);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('Brakes'), findsOneWidget);
  });
  testWidgets('late response from previous workshop cannot replace current inbox', (tester) async {
    final old = Completer<List<GarageRepairRequest>>();
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestsScreen(load: () => old.future)));
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestsScreen(load: () async => const [])));
    await tester.pumpAndSettle();
    old.complete(const [GarageRepairRequest(shop, other, shop, 'Old private title', 'sent')]);
    await tester.pumpAndSettle();
    expect(find.text('Old private title'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });
}
