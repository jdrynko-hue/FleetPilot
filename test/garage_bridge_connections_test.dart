import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/bridge_connections_screen.dart';
import 'package:fleetpilot/garage/repair_bridge_repository.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:fleetpilot/data/models.dart';
const company = '00000000-0000-4000-8000-000000000001';
const shop = '00000000-0000-4000-8000-000000000002';
const issueId = '00000000-0000-4000-8000-000000000003';
const active = GarageFleetConnection(company, shop, 'active', 'Fleet A', 'Garage A');
void main() {
  test('labels reject foreign scope, duplicates and malformed status', () {
    final row = {'company_id':company,'workspace_id':shop,'status':'active',
      'company_name':'Fleet A','workspace_name':'Garage A'};
    expect(GarageFleetConnection.parseList([row], shop, fleet: true), isEmpty);
    expect(GarageFleetConnection.parseList([row], shop, fleet: false).single.companyName, 'Fleet A');
    expect(() => GarageFleetConnection.parseList([row,row], company, fleet: true), throwsFormatException);
    expect(() => GarageFleetConnection.parseList([{...row,'status':'verified'}], company, fleet: true), throwsFormatException);
  });
  testWidgets('published search requests consent only after confirmation', (tester) async {
    var writes = 0;
    await tester.pumpWidget(MaterialApp(home: GarageBridgeConnectionsScreen(fleet: true,
      load: () async => [], connect: (s,c) async { expect(s,shop); writes++; return shop; },
      search: (city) async => const [GarageBookingWorkshop(workspaceId:shop,name:'Garage A',
        city:'Luton',country:'GB',timeZone:'Europe/London',services:['brakes'])],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garage A'));
    await tester.pumpAndSettle();
    expect(writes,0);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(writes,1);
  });
  testWidgets('defect defaults to title-only and requires selection', (tester) async {
    (bool,bool)? flags;
    final issue = FleetIssue(id:issueId,companyId:company,vehicleId:shop,title:'Brakes',
      priority:'high',status:'open',reportedAt:DateTime.utc(2026));
    await tester.pumpWidget(MaterialApp(home: GarageBridgeConnectionsScreen(fleet:true,
      load:() async => [active], connect:(_,__) async => shop,
      loadIssues:() async => [issue], send:(s,i,d,r) async { flags=(d,r); return issueId; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garage A'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('bridge_send_confirm'))).onPressed,isNull);
    expect(tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)).every((c) => c.value==false),isTrue);
    await tester.tap(find.byType(DropdownButtonFormField<FleetIssue>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brakes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bridge_send_confirm')));
    await tester.pumpAndSettle();
    expect(flags,(false,false));
  });
  testWidgets('fleet manager can revoke active connection only after confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var revokes = 0;
    var revoked = false;
    await tester.pumpWidget(MaterialApp(home: GarageBridgeConnectionsScreen(
      fleet: true,
      load: () async => [
        GarageFleetConnection(company, shop, revoked ? 'revoked' : 'active',
          'Fleet A', 'Garage A'),
      ],
      connect: (_, __) async => shop,
      revoke: (row) async {
        expect(row.companyId, company);
        expect(row.workspaceId, shop);
        expect(row.status, 'active');
        revokes++;
        revoked = true;
        return true;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bridge_revoke_${company}_${shop}')));
    await tester.pumpAndSettle();
    expect(revokes, 0);
    expect(find.textContaining('Past actions remain'), findsOneWidget);
    expect(find.textContaining('cannot be restored from the app'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bridge_revoke_confirm')));
    await tester.pumpAndSettle();
    expect(revokes, 1);
    expect(find.text('Connection revoked. The list has been refreshed.'),
      findsOneWidget);
    expect(find.text('Revoke access'), findsNothing);
    expect(find.byKey(const Key('bridge_revoke_${company}_${shop}')),
      findsNothing);
  });

  testWidgets('workshop owner can cancel revocation without writing',
      (tester) async {
    var revokes = 0;
    await tester.pumpWidget(MaterialApp(home: GarageBridgeConnectionsScreen(
      fleet: false,
      load: () async => [active],
      connect: (_, __) async => shop,
      revoke: (_) async { revokes++; return true; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bridge_revoke_${company}_${shop}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(revokes, 0);
    expect(find.byKey(const Key('bridge_revoke_${company}_${shop}')),
      findsOneWidget);
  });

  testWidgets('revocation re-reads server status before mutation',
      (tester) async {
    var loads = 0;
    var revokes = 0;
    await tester.pumpWidget(MaterialApp(home: GarageBridgeConnectionsScreen(
      fleet: true,
      load: () async => ++loads == 1 ? [active] : [],
      connect: (_, __) async => shop,
      revoke: (_) async { revokes++; return true; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bridge_revoke_${company}_${shop}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bridge_revoke_confirm')));
    await tester.pumpAndSettle();
    expect(revokes, 0);
    expect(loads, 3);
    expect(find.byKey(const Key('bridge_revoke_${company}_${shop}')),
      findsNothing);
  });

  testWidgets('uncertain revocation hides stale access and never retries',
      (tester) async {
    var revokes = 0;
    var loads = 0;
    await tester.pumpWidget(MaterialApp(home: GarageBridgeConnectionsScreen(
      fleet: true,
      load: () async {
        loads++;
        return [active];
      },
      connect: (_, __) async => shop,
      revoke: (_) async {
        revokes++;
        throw StateError('network timeout after server commit');
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bridge_revoke_${company}_${shop}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bridge_revoke_confirm')));
    await tester.pumpAndSettle();
    expect(revokes, 1);
    expect(loads, 2);
    expect(find.textContaining('Revocation outcome is uncertain'),
      findsOneWidget);
    expect(find.byKey(const Key('bridge_revoke_${company}_${shop}')),
      findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revoked connection cannot send defects', (tester) async {
    var loads=0; var writes=0;
    final issue=FleetIssue(id:issueId,companyId:company,vehicleId:shop,title:'Brakes',
      priority:'high',status:'open',reportedAt:DateTime.utc(2026));
    await tester.pumpWidget(MaterialApp(home: GarageBridgeConnectionsScreen(fleet:true,
      load:() async => ++loads==1 ? [active] : [], connect:(_,__) async => shop,
      loadIssues:() async => [issue], send:(s,i,d,r) async { writes++; return issueId; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garage A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<FleetIssue>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brakes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bridge_send_confirm')));
    await tester.pumpAndSettle();
    expect(writes,0);
  });
}
