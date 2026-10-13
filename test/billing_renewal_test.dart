import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:fleetpilot/company/billing_screen.dart';
import 'package:fleetpilot/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  bool storedCancellation = false;
  bool failMutation = false;
  String countryCode = 'GB';
  String storedStripeMode = 'test';
  int subscriptionReads = 0;
  final actions = <String>[];

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => call.method == 'getAll' ? <String, Object>{} : true,
    );
    await Supabase.initialize(
      url: 'https://qa.example.com',
      publishableKey: 'qa-publishable-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        Object body;
        int status = 200;
        switch (request.url.path) {
          case '/rest/v1/companies':
            body = {'country': countryCode};
          case '/rest/v1/rpc/get_company_entitlements':
            body = [{'subscription_status': 'active', 'vehicle_count': 0}];
          case '/rest/v1/company_subscriptions':
            subscriptionReads++;
            body = {
              'plan_code': 'pro', 'status': 'active',
              'billing_provider': 'stripe', 'stripe_subscription_id': 'sub_qa',
              'stripe_price_id': 'price_qa', 'billing_interval': 'monthly',
              'billable_vehicle_count': 10,
              'cancel_at_period_end': storedCancellation,
              'current_period_end': '2026-11-12T18:58:23Z',
            };
          case '/rest/v1/flotaryx_billing_prices':
            body = request.url.queryParameters['select'] == 'stripe_mode'
                ? [{'stripe_mode': storedStripeMode}]
                : [{
                    'plan_code': 'pro', 'billing_interval': 'month',
                    'included_vehicles': 10, 'max_vehicles': 25,
                    'base_amount_minor': countryCode == 'PL' ? 30900 : 5900,
                    'extra_vehicle_amount_minor': 500,
                  }];
          case '/functions/v1/flotaryx-billing-manage':
            final action = (jsonDecode(request.body) as Map)['action'] as String;
            actions.add(action);
            status = failMutation ? 503 : 200;
            body = failMutation
                ? {'error': 'Stripe temporarily unavailable'}
                : {'ok': true, 'cancellation_scheduled': action == 'cancel',
                    'period_end': '2026-11-12T18:58:23Z'};
          default:
            throw StateError('Unexpected request: ${request.url.path}');
        }
        return http.Response(jsonEncode(body), status,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );
  });

  setUp(() {
    storedCancellation = false;
    failMutation = false;
    countryCode = 'GB';
    storedStripeMode = 'test';
    subscriptionReads = 0;
    actions.clear();
  });

  Future<void> openBilling(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: BillingScreen(
      company: CompanyMembership(companyId: 'qa-company',
          companyName: 'Flotaryx QA Sandbox', role: 'owner', currency: 'GBP'),
    )));
    await tester.pumpAndSettle();
    expect(find.text(storedCancellation ? 'Resume renewal' : 'Cancel renewal'),
        findsOneWidget, reason: tester.widgetList<Text>(find.byType(Text))
            .map((text) => text.data).join(' | '));
  }

  Future<void> settleMutation(WidgetTester tester) async {
    // FunctionsClient JSON serialization runs outside Flutter's fake clock.
    for (var stage = 0; stage < 3; stage++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
    }
  }

  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(find.text('Cancel renewal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await settleMutation(tester);
  }

  testWidgets('cancel and resume update without waiting for the webhook', (tester) async {
    await openBilling(tester);
    await cancel(tester);
    expect(find.text('Resume renewal'), findsOneWidget,
        reason: tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | ') + ' actions=$actions');
    expect(find.textContaining('Cancellation scheduled at period end.'), findsOneWidget);
    expect(subscriptionReads, 1);
    // Supabase still says false: no webhook has arrived.
    expect(storedCancellation, isFalse);
    await tester.tap(find.text('Resume renewal'));
    await settleMutation(tester);
    expect(find.text('Cancel renewal'), findsOneWidget,
        reason: tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | ') + ' actions=$actions');
    expect(find.textContaining('Cancellation scheduled at period end.'), findsNothing);
    expect(actions, ['cancel', 'resume']);
    expect(subscriptionReads, 1);
  });

  testWidgets('resume updates while Supabase still reports cancellation', (tester) async {
    storedCancellation = true;
    await openBilling(tester);
    await tester.tap(find.text('Resume renewal'));
    await settleMutation(tester);
    expect(find.text('Cancel renewal'), findsOneWidget);
    expect(storedCancellation, isTrue);
    expect(subscriptionReads, 1);
  });

  testWidgets('failed cancellation preserves the current renewal state', (tester) async {
    failMutation = true;
    await openBilling(tester);
    await cancel(tester);
    expect(find.text('Cancel renewal'), findsOneWidget);
    expect(find.text('Resume renewal'), findsNothing);
    expect(actions, ['cancel']);
    expect(find.textContaining('Stripe temporarily unavailable'), findsOneWidget);
  });

  testWidgets('Sandbox displays GBP and no-real-charge warning', (tester) async {
    await openBilling(tester);
    expect(find.text('SANDBOX — NO REAL CHARGES'), findsOneWidget);
    expect(find.text('Currency: GBP'), findsOneWidget);
    expect(find.text('£59.00'), findsOneWidget);
    expect(actions, isEmpty);
  });

  testWidgets('Polish fleets display PLN instead of GBP', (tester) async {
    countryCode = 'PL';
    await openBilling(tester);
    expect(find.text('SANDBOX — NO REAL CHARGES'), findsOneWidget);
    expect(find.text('Currency: PLN'), findsOneWidget);
    expect(find.text('309.00 zł'), findsOneWidget);
    expect(find.text('£59.00'), findsNothing);
    expect(actions, isEmpty);
  });

  testWidgets('Unknown Stripe price environment fails closed', (tester) async {
    storedStripeMode = 'unexpected';
    await tester.pumpWidget(MaterialApp(home: BillingScreen(
      company: CompanyMembership(companyId: 'qa-company',
          companyName: 'Flotaryx QA Sandbox', role: 'owner', currency: 'GBP'),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Existing subscription price has an unknown Stripe environment'),
        findsOneWidget);
    expect(find.text('Cancel renewal'), findsNothing);
    expect(actions, isEmpty);
  });

  testWidgets('Unsupported country cannot open subscription purchase', (tester) async {
    countryCode = 'US';
    await tester.pumpWidget(MaterialApp(home: BillingScreen(
      company: CompanyMembership(companyId: 'qa-company',
          companyName: 'Flotaryx QA Sandbox', role: 'owner', currency: 'USD'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Billing is not available in your company country yet.'),
        findsOneWidget);
    expect(find.text('Cancel renewal'), findsNothing);
    expect(actions, isEmpty);
  });

}
