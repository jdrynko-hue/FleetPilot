// Actual application root + real Auth and tenant APIs, disposable CI only.
import 'dart:io';
import 'package:http/io_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fleetpilot/app.dart';
import 'package:fleetpilot/auth/login_screen.dart';
import 'package:fleetpilot/core/app_config.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/ecosystem/ecosystem_gate.dart';
import 'package:fleetpilot/garage/bridge_connections_screen.dart';
import 'package:fleetpilot/garage/consumer_booking_screen.dart';
import 'package:fleetpilot/shell/fleet_app_bar.dart';
import 'package:fleetpilot/shell/fleet_shell.dart';

class _LocalNavigationBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}
void main() {
  _LocalNavigationBinding();
  final api = Platform.environment['GARAGE_TEST_API_URL'] ?? '';
  final anon = Platform.environment['GARAGE_TEST_ANON_KEY'] ?? '';
  if (!RegExp(r'^http://(127\.0\.0\.1|localhost):\d+$').hasMatch(api) ||
      anon.isEmpty || !AppConfig.ecosystemQaEnabled || !AppConfig.isConfigured) {
    throw StateError('Requires loopback API and explicit QA navigation build flags');
  }
  final clients = <SupabaseClient>[];
  final transports = <HttpClient>[];
  var singletonClosed = false;
  setUpAll(() async {
    for (final channel in ['plugins.flutter.io/shared_preferences', 'com.llfbandit.app_links/events']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(channel), (call) async =>
          channel == 'plugins.flutter.io/shared_preferences'
            ? (call.method == 'getAll' ? <String, Object>{} : true) : null);
    }
    final transport = HttpClient()..idleTimeout = Duration.zero;
    transports.add(transport);
    await Supabase.initialize(url: api, publishableKey: anon,
      httpClient: IOClient(transport),
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit,
        autoRefreshToken: false, localStorage: EmptyLocalStorage(), detectSessionInUri: false));
  });
  tearDownAll(() async {
    if (!singletonClosed) await Supabase.instance.dispose();
    for (final client in clients) { await client.dispose(); }
    for (final transport in transports) { transport.close(force: true); }
  });
  testWidgets('root login, two workshops, account switch, two fleets and logout', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppLocale.language.value = 'en';
    const password = 'DisposableNavigation-QA-2026!';
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final names = ['Navigation Fleet A $suffix', 'Navigation Fleet B $suffix'];
    final garageNames = ['Navigation Garage A $suffix', 'Navigation Garage B $suffix'];
    final companies = <String>[];
    final shops = <String>[];
    late SupabaseClient fleet, owner, customer;
    Future<SupabaseClient> actor(String role) async {
      final transport = HttpClient()..idleTimeout = Duration.zero;
      transports.add(transport);
      final client = SupabaseClient(api, anon, httpClient: IOClient(transport),
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit, autoRefreshToken: false));
      clients.add(client);
      final result = await client.auth.signUp(email: 'nav-$role-$suffix@example.test', password: password);
      if (result.session == null) throw StateError('Local signup did not return session');
      return client;
    }
    await tester.runAsync(() async {
      fleet = await actor('fleet'); owner = await actor('owner'); customer = await actor('customer');
      // User-editable metadata must not turn a consumer into workshop staff.
      await customer.auth.updateUser(UserAttributes(data: {'role': 'owner', 'is_admin': true}));
      for (var i = 0; i < 2; i++) {
        companies.add(await fleet.rpc('create_company_for_current_user', params: {
          '_name': names[i], '_country': 'GB', '_currency': 'GBP',
        }) as String);
        shops.add((await owner.from('garage_workspaces').insert({
          'owner_user_id': owner.auth.currentUser!.id, 'name': garageNames[i],
          'country': 'GB', 'currency': 'GBP',
        }).select('id').single())['id'] as String);
        await fleet.rpc('garage_fleet_request_connection', params: {'p_company': companies[i], 'p_shop': shops[i]});
      }
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
      await see(finder, 'navigation tap');
      await tester.ensureVisible(finder); await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 300));
    }
    Future<void> login(SupabaseClient actor) async {
      await see(find.byType(LoginScreen), 'login screen');
      await tester.enterText(find.byType(TextFormField).at(0), actor.auth.currentUser!.email!);
      await tester.enterText(find.byType(TextFormField).at(1), password);
      await tap(find.byType(FilledButton));
      await see(find.byKey(const Key('ecosystem_customer')), 'authenticated module chooser');
    }
    await tester.pumpWidget(const FleetPilotApp());
    await login(customer);
    expect(find.byType(FleetShell), findsNothing);
    for (final shop in shops) { expect(find.byKey(Key('ecosystem_$shop')), findsNothing); }
    await tap(find.byKey(const Key('ecosystem_customer')));
    await tap(find.text('Find a workshop'));
    await see(find.byType(GarageBookingSearchScreen), 'consumer search without fleet');
    expect(find.byType(FleetShell), findsNothing);
    await tester.runAsync(() => Supabase.instance.client.auth.signOut());
    await see(find.byType(LoginScreen), 'logout closes private customer routes');
    await until(() => find.byType(GarageBookingSearchScreen).evaluate().isEmpty,
      'customer route disposal after logout transition');

    await login(owner);
    for (var i = 0; i < 2; i++) {
      await tap(find.byKey(Key('ecosystem_${shops[i]}')));
      await tap(find.text('Fleet connections'));
      await see(find.byType(GarageBridgeConnectionsScreen), 'workshop connections');
      await see(find.text(names[i]), 'own workshop fleet');
      expect(find.text(names[1-i]), findsNothing);
      if (i == 0) {
        await tester.pageBack(); await tester.pump(const Duration(milliseconds: 400));
        await tester.pageBack(); await tester.pump(const Duration(milliseconds: 400));
        await see(find.byKey(Key('ecosystem_${shops[1]}')), 'return to workshop chooser');
      }
    }
    // A server session/account change while two private routes are pushed.
    await tester.runAsync(() => Supabase.instance.client.auth.signInWithPassword(
      email: fleet.auth.currentUser!.email!, password: password));
    await see(find.byKey(const Key('ecosystem_fleet')), 'new Fleet identity');
    await until(() => find.byType(GarageBridgeConnectionsScreen).evaluate().isEmpty, 'old account route removed');
    expect(find.text(names[1]), findsNothing);
    for (final shop in shops) { expect(find.byKey(Key('ecosystem_$shop')), findsNothing); }
    expect(find.byType(EcosystemGate), findsOneWidget);
    await tap(find.byKey(const Key('ecosystem_fleet')));
    await see(find.byKey(const Key('fleet_company_selector')), 'real Fleet shell');
    await tap(find.byKey(const Key('fleet_company_selector')));
    await tap(find.text(names[1]).last);
    await until(() => tester.widget<FleetAppBar>(find.byType(FleetAppBar)).selectedMembership.companyId == companies[1],
      'second fleet selected');
    await tap(find.byKey(const Key('fleet_mobile_menu')));
    await tap(find.byKey(const Key('fleet_menu_signout')));
    await see(find.byType(LoginScreen), 'Fleet logout returns to login');
    await until(() => find.byType(FleetShell).evaluate().isEmpty,
      'Fleet route disposal after logout transition');
    expect(find.byType(EcosystemGate), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    // Dispose all real transports before widget-test timer verification.
    await tester.runAsync(() async {
      await Supabase.instance.dispose();
      singletonClosed = true;
      for (final client in clients) { await client.dispose(); }
      clients.clear();
      for (final transport in transports) { transport.close(force: true); }
      transports.clear();
    });
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
