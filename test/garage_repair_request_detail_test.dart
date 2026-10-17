import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/repair_bridge_repository.dart';
import 'package:fleetpilot/garage/repair_requests_screen.dart';
import 'garage_repair_bridge_repository_test.dart' as fixture;
import 'package:fleetpilot/garage/resource_calendar_repository.dart';

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

  testWidgets('diagnosis requires confirmation and fresh accepted order', (tester) async {
    var status = 'received';
    var writes = 0;
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row, load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status: 'accepted', workOrderId: fixture.orderId, orderStatus: status)),
      advance: (data, target) async {
        expect(data.workOrderId, fixture.orderId);
        writes++; status = target; return target;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair_advance_diagnosing')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.byKey(const Key('repair_advance_diagnosing')), findsNothing);
  });
  testWidgets('unapproved current estimate cannot start repair', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row, load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status: 'accepted', workOrderId: fixture.orderId, orderStatus: 'awaiting_approval',
        estimate: fixture.quote())), advance: (_, target) async => target,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('repair_advance_in_progress')), findsNothing);
  });
  testWidgets('new unapproved revision during start confirmation prevents write', (tester) async {
    var loads = 0;
    var writes = 0;
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row, load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status: 'accepted', workOrderId: fixture.orderId, orderStatus: 'awaiting_approval',
        estimate: fixture.quote(approved: ++loads == 1))),
      advance: (_, target) async { writes++; return target; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair_advance_in_progress')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.byKey(const Key('repair_advance_in_progress')), findsNothing);
  });
  testWidgets('owner must choose a verified mechanic before assigning', (tester) async {
    String? assigned;
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row, load: () async => accepted(),
      loadMechanics: () async => const [GarageRosterMechanic(userId: fixture.issueId, email: 'mechanic@example.test')],
      assign: (data, mechanic) async { assigned = mechanic; return mechanic; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('repair_assign')));
    await tester.pumpAndSettle();
    final confirm = find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('mechanic@example.test').last);
    await tester.pumpAndSettle();
    expect(assigned, isNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(assigned, fixture.issueId);
  });

  testWidgets('Fleet sees mechanic assignment but never workshop identity',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row,
      load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status:'accepted', workOrderId:fixture.orderId,
        orderStatus:'diagnosing', assigned:true)),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('repair_assigned_mechanic')), findsOneWidget);
    expect(find.text('Mechanic assigned'), findsOneWidget);
    expect(find.textContaining('mechanic@example.test'), findsNothing);
    expect(find.textContaining(fixture.issueId), findsNothing);
  });

  testWidgets('workshop roster resolves assigned mechanic without exposing ID',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row,
      load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status:'accepted', workOrderId:fixture.orderId,
        orderStatus:'diagnosing', assigned:true, mechanic:fixture.issueId)),
      loadMechanics: () async => const [
        GarageRosterMechanic(userId:fixture.issueId,
          email:'mechanic@example.test'),
      ],
    )));
    await tester.pumpAndSettle();
    expect(find.text('mechanic@example.test'), findsOneWidget);
    expect(find.textContaining(fixture.issueId), findsNothing);
  });

  testWidgets('slow roster does not block authorized repair actions',
      (tester) async {
    final roster = Completer<List<GarageRosterMechanic>>();
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row,
      load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status:'accepted',workOrderId:fixture.orderId,
        orderStatus:'awaiting_approval', assigned:true,
        mechanic:fixture.issueId,
        estimate:fixture.quote(approved:true))),
      loadMechanics: () => roster.future,
      advance: (data, target) async => target,
    )));
    await tester.pump();
    await tester.pump();
    expect(find.text('Mechanic assigned'), findsOneWidget);
    final start = tester.widget<FilledButton>(
      find.byKey(const Key('repair_advance_in_progress')));
    expect(start.onPressed, isNotNull);
    roster.complete(const [GarageRosterMechanic(
      userId:fixture.issueId, email:'mechanic@example.test')]);
    await tester.pumpAndSettle();
    expect(find.text('mechanic@example.test'), findsOneWidget);
  });

  testWidgets('workshop keeps generic label when roster cannot load',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row,
      load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status:'accepted', workOrderId:fixture.orderId,
        orderStatus:'diagnosing', assigned:true, mechanic:fixture.issueId)),
      loadMechanics: () async => throw StateError('private API message'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Mechanic assigned'), findsOneWidget);
    expect(find.textContaining('private API message'), findsNothing);
  });

  testWidgets('chronological repair timeline shows safe events and revisions',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: GarageRepairRequestDetailScreen(
      request: row,
      load: () async => GarageRepairBridgeSnapshot.parse(fixture.snapshot(
        status:'accepted',workOrderId:fixture.orderId,orderStatus:'ready',
        estimate:fixture.quote(approved:true),
        assigned:true,
        history:[
          fixture.event('request_sent','2026-10-14T09:00:00Z'),
          fixture.event('request_accepted','2026-10-14T09:01:00Z'),
          fixture.event('quote_approved','2026-10-14T09:02:00Z'),
          fixture.event('progress_updated','2026-10-14T09:03:00Z'),
        ],
      )),
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('repair_event_timeline')));
    await tester.tap(find.byKey(const Key('repair_event_timeline')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('repair_timeline_event_0')), findsOneWidget);
    expect(find.text('Request sent'), findsOneWidget);
    expect(find.text('Workshop accepted'), findsOneWidget);
    expect(find.text('Estimate approved'), findsOneWidget);
    expect(find.textContaining('Estimate revision: 1'), findsOneWidget);
    expect(find.textContaining('In progress → Ready for collection'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
