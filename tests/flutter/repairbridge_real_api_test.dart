// Explicit opt-in integration suite: real Flutter widgets + loopback Supabase.
// Outside test/ so normal offline regression never attempts network access.
import 'dart:io';
import 'package:http/io_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/data/models.dart';
import 'package:fleetpilot/garage/bridge_connections_screen.dart';
import 'package:fleetpilot/garage/repair_requests_screen.dart';
import 'package:fleetpilot/garage/repair_bridge_repository.dart';
import 'package:fleetpilot/garage/workshop_quotes_screen.dart';

class _LocalApiBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _LocalApiBinding();
  final api = Platform.environment['GARAGE_TEST_API_URL'] ?? '';
  final anon = Platform.environment['GARAGE_TEST_ANON_KEY'] ?? '';
  if (!RegExp(r'^http://(127\.0\.0\.1|localhost):\d+$').hasMatch(api) || anon.isEmpty) {
    throw StateError('Only explicit disposable loopback Supabase is allowed');
  }
  AppLocale.language.value = 'en';

  for (final width in [390.0, 412.0]) {
    testWidgets('real API repair lifecycle at phone width $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clients = <SupabaseClient>[];
      final transports = <HttpClient>[];
      Future<void> closeClients() async {
        for (final client in clients) { await client.dispose(); }
        clients.clear();
        for (final transport in transports) { transport.close(force: true); }
        transports.clear();
      }
      addTearDown(closeClients);
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      Future<SupabaseClient> actor(String role) async {
        // Disposable password signups do not use browser PKCE redirects/storage.
        final transport = HttpClient()..idleTimeout = Duration.zero;
        transports.add(transport);
        final client = SupabaseClient(api, anon, httpClient: IOClient(transport),
          authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit, autoRefreshToken: false));
        clients.add(client);
        final response = await client.auth.signUp(email: 'flutter-$role-$suffix@example.test',
          password: 'DisposableFlutter-QA-2026!');
        if (response.session == null) throw StateError('Local signup needs session');
        return client;
      }
      late SupabaseClient fleet, owner, mechanic, outsider;
      late String company, shop, mechanicId;
      final garageName = 'Flutter Garage $suffix';
      final fleetName = 'Flutter Fleet $suffix';
      final title = 'Flutter brake defect $suffix';
      await tester.runAsync(() async {
        fleet = await actor('fleet'); owner = await actor('owner');
        mechanic = await actor('mechanic'); outsider = await actor('outsider');
        company = await fleet.rpc('create_company_for_current_user', params: {
          '_name': fleetName, '_country': 'GB', '_currency': 'GBP',
        }) as String;
        final vehicle = await fleet.from('vehicles').insert({
          'company_id': company, 'registration': 'QA-$width-$suffix',
        }).select('id').single();
        await fleet.from('issues').insert({'company_id': company, 'vehicle_id': vehicle['id'],
          'title': title, 'description': 'Unshared private description'});
        shop = (await owner.from('garage_workspaces').insert({
          'owner_user_id': owner.auth.currentUser!.id, 'name': garageName,
          'country': 'GB', 'currency': 'GBP',
        }).select('id').single())['id'] as String;
        await owner.rpc('garage_booking_configure', params: {
          'p_workspace': shop, 'p_city': 'FlutterQA$suffix', 'p_time_zone': 'Europe/London',
          'p_services': ['brakes'], 'p_duration': 60, 'p_listed': true,
        });
        final token = await owner.rpc('garage_issue_staff_invite', params: {
          'p_workspace_id': shop, 'p_email': mechanic.auth.currentUser!.email, 'p_role': 'mechanic',
        });
        await mechanic.rpc('garage_accept_staff_invite', params: {'p_token': token});
        mechanicId = mechanic.auth.currentUser!.id;
      });
      expect(tester.takeException(), isNull);

      Future<void> until(bool Function() ready, String context) async {
        for (var i = 0; i < 300; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await tester.pump(const Duration(milliseconds: 30));
          final error = tester.takeException();
          if (error != null) throw TestFailure('$context: $error');
          if (ready()) return;
        }
        throw TestFailure('Timed out: $context');
      }
      Future<void> see(Finder finder, String context) => until(() => finder.evaluate().isNotEmpty, context);
      Future<void> tap(Finder finder) async {
        await see(finder, 'tap target');
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 300));
      }
      Future<void> confirm() async {
        await see(find.byType(AlertDialog), 'confirmation');
        await tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      }
      Future<void> mount(Widget screen) async {
        await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: screen));
        await tester.pump();
      }
      Widget connections(SupabaseClient client, bool isFleet) => GarageBridgeConnectionsScreen.forClient(
        client: client, scopeId: isFleet ? company : shop, fleet: isFleet);
      Widget requests(SupabaseClient client, bool isFleet) => GarageRepairRequestsScreen.forClient(
        client: client, workspaceId: isFleet ? company : shop, fleet: isFleet, canAssign: !isFleet);

      await mount(connections(fleet, true));
      await until(() => find.byType(OutlinedButton).evaluate().isNotEmpty &&
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed != null, 'connection load');
      await tester.enterText(find.byType(TextField), 'FlutterQA$suffix');
      await tap(find.byType(OutlinedButton));
      await tap(find.text(garageName));
      await confirm();
      await see(find.text('Awaiting workshop consent'), 'pending consent');

      await mount(connections(owner, false));
      await tap(find.text(fleetName));
      await confirm();
      await see(find.text('Connection active'), 'owner consent');

      await mount(connections(fleet, true));
      await tap(find.text(garageName));
      await see(find.byType(DropdownButtonFormField<FleetIssue>), 'real Fleet issues query');
      await tap(find.byType(DropdownButtonFormField<FleetIssue>));
      await tap(find.text(title).last);
      expect(tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)).every((r) => r.value == false), isTrue);
      await tap(find.byKey(const Key('bridge_send_confirm')));
      await see(find.textContaining('Request sent.'), 'defect handoff');

      late String requestId;
      await tester.runAsync(() async {
        final rows = await GarageRepairBridgeRepository(fleet).fleetRequests(company);
        expect(rows, hasLength(1)); requestId = rows.single.id;
        final data = await GarageRepairBridgeRepository(fleet).load(requestId);
        expect(data.sharedDescription, isNull); expect(data.sharedRegistration, isNull);
        expect(await GarageRepairBridgeRepository(outsider).fleetRequests(company), isEmpty);
      });
      expect(tester.takeException(), isNull);

      await mount(requests(owner, false));
      await tap(find.text(title));
      await tap(find.byKey(const Key('repair_accept')));
      await confirm();
      await tap(find.byKey(const Key('repair_advance_diagnosing')));
      await confirm();
      await see(find.text('Diagnosing'), 'diagnosis status');
      await tap(find.byKey(const Key('repair_assign')));
      await tap(find.byType(DropdownButtonFormField<String>));
      await tap(find.text(mechanic.auth.currentUser!.email!).last);
      await confirm();
      await until(() => find.byType(AlertDialog).evaluate().isEmpty &&
        find.byKey(const Key('repair_assign')).evaluate().isNotEmpty &&
        tester.widget<OutlinedButton>(find.byKey(const Key('repair_assign'))).onPressed != null,
        'assignment read-back');

      await mount(GarageWorkshopQuotesScreen.forClient(client: owner, workspaceId: shop));
      await tap(find.text(title));
      await see(find.byKey(const Key('quote_description_0')), 'quote editor');
      await tester.enterText(find.byKey(const Key('quote_description_0')), 'Brake service');
      await tester.enterText(find.byKey(const Key('quote_unit_0')), '60');
      await tester.enterText(find.byKey(const Key('quote_tax_0')), '12');
      await tap(find.byKey(const Key('quote_publish')));
      await tap(find.byKey(const Key('garage_editor_confirm')));
      await see(find.byKey(const Key('quote_editor_success')), 'published real quote');

      await mount(requests(fleet, true));
      await tap(find.text(title));
      await tap(find.byKey(const Key('repair_review_quote')));
      await see(find.byKey(const Key('garage_quote_total')), 'manager quote');
      expect(find.text('£72.00'), findsWidgets);
      await tap(find.byKey(const Key('garage_quote_approve')));
      await tap(find.byKey(const Key('garage_quote_confirm')));
      await see(find.text('Approved'), 'manager approved revision');

      await mount(requests(owner, false));
      await tap(find.text(title));
      await tap(find.byKey(const Key('repair_advance_in_progress')));
      await confirm();
      await tap(find.byKey(const Key('repair_progress_ready')));
      await confirm();
      await tap(find.byKey(const Key('repair_progress_collected')));
      await confirm();
      await until(() => find.byKey(const Key('repair_current_status')).evaluate().isNotEmpty &&
        tester.widget<Text>(find.byKey(const Key('repair_current_status'))).data == 'Collected',
        'server-confirmed collected status');
      await tester.runAsync(() async {
        final data = await GarageRepairBridgeRepository(fleet).load(requestId);
        expect(data.workOrderStatus, 'collected'); expect(data.quote!.approved, isTrue);
        final order = await owner.from('garage_work_orders').select('assigned_user_id')
          .eq('id', data.workOrderId!).eq('workspace_id', shop).single();
        expect(order['assigned_user_id'], mechanicId);
        expect(await GarageRepairBridgeRepository(outsider).requests(shop), isEmpty);
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      // Close sockets before Flutter verifies that no fake-clock timers remain.
      await tester.runAsync(closeClients);
      await tester.pump();
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
