import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/repair_bridge_repository.dart';
import 'package:fleetpilot/garage/repair_requests_screen.dart';
import 'garage_repair_bridge_repository_test.dart' as fixture;

const row = GarageRepairRequest(fixture.requestId, fixture.companyId,
    fixture.workshopId, 'Brakes', 'sent');
GarageRepairBridgeSnapshot sent() => GarageRepairBridgeSnapshot.parse(fixture.snapshot());
GarageRepairBridgeSnapshot accepted() => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
  status: 'accepted', workOrderId: fixture.orderId, orderStatus: 'received'));

void main() {
  testWidgets('acceptance requires confirmation, writes once and reloads status', (tester) async {
    var writes = 0;
    final pending = Completer<String>();
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row, load: () async => writes == 0 ? sent() : accepted(),
      accept: () { writes++; return pending.future; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair_accept')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pump();
    await tester.pump();
    expect(writes, 1);
    expect(tester.widget<FilledButton>(find.byKey(const Key('repair_accept'))).onPressed, isNull);
    pending.complete(fixture.orderId);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('repair_accept')), findsNothing);
    expect(writes, 1);
  });
  testWidgets('wrong workshop response cannot display private details or enable writes', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row, load: () async => GarageRepairBridgeSnapshot.parse({
        ...fixture.snapshot(), 'workspace_id': fixture.companyId,
        'issue_title': 'Private other workshop',
      }), accept: () async => fixture.orderId,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Private other workshop'), findsNothing);
    expect(find.byKey(const Key('repair_accept')), findsNothing);
  });
  testWidgets('ambiguous write failure requires read-back and never retries automatically', (tester) async {
    var writes = 0;
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row, load: () async => sent(), accept: () async {
        writes++; throw StateError('private backend message');
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair_accept')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.textContaining('private backend message'), findsNothing);
    expect(find.byKey(const Key('repair_accept')), findsNothing);
    expect(find.byType(TextButton), findsOneWidget);
  });
  testWidgets('revoked consent during preflight prevents acceptance', (tester) async {
    var loads = 0;
    var writes = 0;
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row, load: () async {
        if (++loads > 1) throw StateError('revoked');
        return sent();
      }, accept: () async { writes++; return fixture.orderId; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair_accept')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.byKey(const Key('repair_accept')), findsNothing);
  });
  testWidgets('progress confirms transition and reads status back', (tester) async {
    var current = 'in_progress';
    var writes = 0;
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row, load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status: 'accepted', workOrderId: fixture.orderId, orderStatus: current)),
      progress: (status) async { writes++; current = status; return status; },
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('repair_progress_collected')), findsNothing);
    await tester.tap(find.byKey(const Key('repair_progress_ready')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.byKey(const Key('repair_progress_ready')), findsNothing);
    expect(find.byKey(const Key('repair_progress_collected')), findsOneWidget);
  });
  testWidgets('concurrent status change prevents stale progress write', (tester) async {
    var loads = 0;
    var writes = 0;
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row, load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status: 'accepted', workOrderId: fixture.orderId,
        orderStatus: ++loads == 1 ? 'in_progress' : 'collected')),
      progress: (status) async { writes++; return status; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair_progress_ready')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.byType(OutlinedButton), findsNothing);
  });
  testWidgets('Fleet review approves exact revision through Fleet callback', (tester) async {
    int? approved;
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row, load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status: 'accepted', workOrderId: fixture.orderId, orderStatus: 'awaiting_approval',
        estimate: fixture.quote(approved: approved != null))),
      approve: (revision) async { approved = revision; return revision; },
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('repair_accept')), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    await tester.tap(find.byKey(const Key('repair_review_quote')));
    await tester.pumpAndSettle();
    final buttons = find.byType(FilledButton);
    await tester.ensureVisible(buttons.first);
    await tester.tap(buttons.first);
    await tester.pumpAndSettle();
    expect(approved, isNull);
    await tester.tap(find.byKey(const Key('garage_quote_confirm')));
    await tester.pumpAndSettle();
    expect(approved, 1);
  });

}
