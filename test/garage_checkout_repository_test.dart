import 'dart:async';
import 'dart:convert';

import 'package:fleetpilot/core/app_config.dart';
import 'package:fleetpilot/garage/checkout_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const qa = 'https://fyestmquqvkdebxxbcky.supabase.co';
  const production = 'https://wqhymmtiawfwjikdaujo.supabase.co';
  const actor = '00000000-0000-4000-8000-000000000001';
  const workspace = '00000000-0000-4000-8000-000000000002';
  const response = <String, Object>{'mode': 'test',
    'session_id': 'cs_test_fixture', 'trial_days': 7,
    'url': 'https://checkout.stripe.com/c/pay/cs_test_fixture#synthetic'};

  GarageCheckoutRepository repository({bool enabled = true, String url = qa,
      String? Function()? user, String? Function()? session,
      GarageCheckoutInvoke? invoke,
      Duration timeout = const Duration(seconds: 12)}) =>
    GarageCheckoutRepository(enabled: enabled, supabaseUrl: url,
      currentUserId: user ?? () => actor,
      currentSessionKey: session ?? () => 'synthetic-session',
      requestTimeout: timeout, invoke: invoke ?? (_) async => response);

  Future<GarageCheckoutResult> start(GarageCheckoutRepository repo, {
      String scope = workspace, String plan = 'garage_qa_pilot',
      String interval = 'month', bool confirmed = true}) => repo.start(
    workspaceId: scope, planCode: plan, billingInterval: interval,
    businessPurchaseConfirmed: confirmed);

  test('Checkout has an independent exact-QA default-off gate', () {
    expect(AppConfig.garageSandboxCheckoutEnabledFor(qa, requested: true), isTrue);
    expect(AppConfig.garageSandboxCheckoutEnabledFor(qa, requested: false), isFalse);
    for (final url in [production, '$qa/', '$qa.evil.test',
      'http://fyestmquqvkdebxxbcky.supabase.co']) {
      expect(AppConfig.garageSandboxCheckoutEnabledFor(url, requested: true), isFalse);
    }
  });

  test('disabled, wrong backend and invalid sessions send no request', () async {
    var calls = 0;
    Future<Object?> invoke(Map<String, Object> _) async { calls++; return response; }
    for (final repo in [
      repository(enabled: false, invoke: invoke),
      repository(url: production, invoke: invoke),
      repository(user: () => null, invoke: invoke),
      repository(user: () => 'forged', invoke: invoke),
      repository(session: () => null, invoke: invoke),
      repository(session: () => '', invoke: invoke),
    ]) {
      expect((await start(repo)).url, isNull);
    }
    expect(calls, 0);
  });

  test('invalid input does not consume the explicit attempt', () async {
    var calls = 0;
    final repo = repository(invoke: (_) async { calls++; return response; });
    expect((await start(repo, scope: 'forged')).state, GarageCheckoutState.unavailable);
    expect((await start(repo, plan: 'PILOT')).url, isNull);
    expect((await start(repo, plan: 'x')).url, isNull);
    expect((await start(repo, interval: 'week')).url, isNull);
    expect((await start(repo, confirmed: false)).url, isNull);
    expect(calls, 0);
    expect((await start(repo)).state, GarageCheckoutState.ready);
    expect(calls, 1);
  });

  test('request contains selection and business confirmation only', () async {
    Map<String, Object>? sent;
    final result = await start(repository(invoke: (body) async {
      sent = body; return response;
    }), interval: 'year');
    expect(sent, {'workspace_id': workspace, 'plan_code': 'garage_qa_pilot',
      'billing_interval': 'year', 'business_purchase_confirmed': true});
    expect(() => sent!['trial_days'] = 30, throwsUnsupportedError);
    expect(result.state, GarageCheckoutState.ready);
    expect(result.url.toString(), response['url']);
    expect(result.toString(), isNot(contains('cs_test_')));
  });

  final badResponses = <String, Object?>{
    'null': null,
    'array': [response],
    'Live mode': {...response, 'mode': 'live'},
    'Live session': {...response, 'session_id': 'cs_live_fixture'},
    'changed trial': {...response, 'trial_days': 30},
    'numeric string trial': {...response, 'trial_days': '7'},
    'floating trial': {...response, 'trial_days': 7.0},
    'extra field': {...response, 'customer_id': 'cus_private'},
    'missing field': {...response}..remove('mode'),
    'wrong session URL': {...response, 'url': 'https://checkout.stripe.com/c/pay/cs_test_other'},
    'HTTP': {...response, 'url': 'http://checkout.stripe.com/c/pay/cs_test_fixture'},
    'lookalike host': {...response, 'url': 'https://checkout.stripe.com.evil.test/c/pay/cs_test_fixture'},
    'credentials': {...response, 'url': 'https://private@checkout.stripe.com/c/pay/cs_test_fixture'},
    'foreign port': {...response, 'url': 'https://checkout.stripe.com:444/c/pay/cs_test_fixture'},
    'whitespace': {...response, 'url': ' ${response['url']}'},
    'backslash': {...response, 'url': 'https://checkout.stripe.com\\evil.test/c/pay/cs_test_fixture'},
    'relative': {...response, 'url': '/c/pay/cs_test_fixture'},
  };
  for (final entry in badResponses.entries) {
    test('rejects ${entry.key} and never automatically retries', () async {
      var calls = 0;
      final repo = repository(invoke: (_) async { calls++; return entry.value; });
      final result = await start(repo);
      expect(result.state, GarageCheckoutState.reconciliationRequired);
      expect(result.url, isNull);
      expect((await start(repo)).url, isNull);
      expect(calls, 1);
    });
  }

  test('double click and plan change during request send exactly once', () async {
    var calls = 0;
    final pending = Completer<Object?>();
    final repo = repository(invoke: (_) { calls++; return pending.future; });
    final first = start(repo);
    expect((await start(repo, interval: 'year')).state,
      GarageCheckoutState.reconciliationRequired);
    expect(calls, 1);
    pending.complete(response);
    expect((await first).state, GarageCheckoutState.ready);
    expect((await start(repo)).state, GarageCheckoutState.reconciliationRequired);
    expect(calls, 1);
  });

  for (final sameUser in [false, true]) {
    test('account/session replacement discards late URL (same user $sameUser)', () async {
      var user = actor;
      String? session = 'old-session';
      final pending = Completer<Object?>();
      final repo = repository(user: () => user, session: () => session,
        invoke: (_) => pending.future);
      final first = start(repo);
      if (!sameUser) user = '00000000-0000-4000-8000-000000000003';
      session = 'new-session';
      pending.complete(response);
      expect((await first).url, isNull);
      expect((await start(repo)).state, GarageCheckoutState.reconciliationRequired);
    });
  }

  test('sign-out while requesting discards late URL', () async {
    String? session = 'old-session';
    final pending = Completer<Object?>();
    final repo = repository(session: () => session, invoke: (_) => pending.future);
    final first = start(repo);
    session = null;
    pending.complete(response);
    expect((await first).url, isNull);
  });

  test('timeout and late success never trigger a second request', () async {
    var calls = 0;
    final pending = Completer<Object?>();
    final repo = repository(timeout: const Duration(milliseconds: 1),
      invoke: (_) { calls++; return pending.future; });
    expect((await start(repo)).state, GarageCheckoutState.reconciliationRequired);
    pending.complete(response);
    expect((await start(repo)).url, isNull);
    expect(calls, 1);
  });

  test('synchronous SDK failure returns an opaque result without retry', () async {
    var calls = 0;
    final repo = repository(invoke: (_) { calls++; throw StateError('PRIVATE'); });
    final result = await start(repo);
    expect(result.state, GarageCheckoutState.reconciliationRequired);
    expect(result.toString(), isNot(contains('PRIVATE')));
    expect((await start(repo)).url, isNull);
    expect(calls, 1);
  });

  test('factory uses authenticated SDK transport, or stays disabled by default', () async {
    var functionCalls = 0;
    final transport = MockClient((request) async {
      if (request.url.path == '/auth/v1/token') {
        final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
        String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value)))
          .replaceAll('=', '');
        final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
          '${part({'sub': actor, 'role': 'authenticated', 'exp': expiry})}.fixture';
        return http.Response(jsonEncode({'access_token': token,
          'refresh_token': 'fixture-refresh', 'token_type': 'bearer',
          'expires_in': 3600, 'expires_at': expiry,
          'user': {'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
            'email': 'fixture@example.test', 'created_at': '2026-10-26T00:00:00Z',
            'app_metadata': <String, Object?>{}, 'user_metadata': <String, Object?>{}}}),
          200, request: request, headers: {'content-type': 'application/json'});
      }
      expect(request.url.host, 'fyestmquqvkdebxxbcky.supabase.co');
      expect(request.url.path, '/functions/v1/flotaryx-garage-test-checkout');
      expect(request.method, 'POST');
      expect(request.headers['authorization'], startsWith('Bearer '));
      expect(jsonDecode(request.body), {'workspace_id': workspace,
        'plan_code': 'garage_qa_pilot', 'billing_interval': 'month',
        'business_purchase_confirmed': true});
      functionCalls++;
      return http.Response(jsonEncode(response), 200, request: request,
        headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient(qa, 'fixture-publishable-key', httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(() async { await client.dispose(); transport.close(); });
    if (AppConfig.garageSandboxCheckoutEnabled) {
      await client.auth.signInWithPassword(email: 'fixture@example.test',
        password: 'fixture-only');
      expect((await start(GarageCheckoutRepository.forClient(client))).state,
        GarageCheckoutState.ready);
      expect(functionCalls, 1);
    } else {
      expect((await start(GarageCheckoutRepository.forClient(client))).state,
        GarageCheckoutState.disabled);
      expect(functionCalls, 0);
    }
  });
}
