import 'dart:async';
import 'dart:convert';

import 'package:fleetpilot/core/app_config.dart';
import 'package:fleetpilot/garage/entitlement_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const qa = 'https://fyestmquqvkdebxxbcky.supabase.co';
  const production = 'https://wqhymmtiawfwjikdaujo.supabase.co';
  const user = '00000000-0000-4000-8000-000000000001';
  const workspace = '00000000-0000-4000-8000-000000000002';
  // Fixed time keeps historical trial response tests deterministic after expiry.
  // Runtime expiry enforcement stays strict and uses the actual clock.
  const activeTrial = <String, Object?>{
    'active': true,
    'source': 'trial',
    'access_ends_at': '2026-10-25T08:00:00Z',
    'last_payment_state': null,
  };

  GarageEntitlementRepository repository({bool enabled = true,
      String url = qa, String? Function()? actor,
      GarageEntitlementInvoke? invoke}) => GarageEntitlementRepository(
    enabled: enabled,
    supabaseUrl: url,
    currentUserId: actor ?? () => user,
    invoke: invoke ?? (_) async => activeTrial,
  );

  test('only an explicit exact QA opt-in can enable the read path', () {
    expect(AppConfig.garageSandboxEntitlementEnabledFor(qa, requested: true),
      isTrue);
    for (final url in [production, 'http://fyestmquqvkdebxxbcky.supabase.co',
      '$qa.evil.test', '$qa/']) {
      expect(AppConfig.garageSandboxEntitlementEnabledFor(url, requested: true),
        isFalse);
    }
    expect(AppConfig.garageSandboxEntitlementEnabledFor(qa, requested: false),
      isFalse);
  });

  test('disabled or wrong-backend repositories make no request', () async {
    var calls = 0;
    Future<Object?> invoke(String _) async { calls++; return activeTrial; }
    expect((await repository(enabled: false, invoke: invoke).load(workspace)).state,
      GarageEntitlementReadState.disabled);
    expect((await repository(url: production, invoke: invoke).load(workspace)).state,
      GarageEntitlementReadState.unavailable);
    expect(calls, 0);
  });

  test('invalid scope or signed-out actor fails closed without a request', () async {
    var calls = 0;
    Future<Object?> invoke(String _) async { calls++; return activeTrial; }
    for (final read in [
      repository(invoke: invoke).load('not-a-workspace'),
      repository(actor: () => null, invoke: invoke).load(workspace),
      repository(actor: () => 'not-a-user', invoke: invoke).load(workspace),
    ]) {
      expect((await read).allowsPaidFeatures, isFalse);
    }
    expect(calls, 0);
  });

  test('only the exact authoritative response shape grants access', () async {
    final accepted = await repository().load(workspace);
    expect(accepted.allowsPaidFeaturesAt(DateTime.utc(2026, 10, 20)), isTrue);
    expect(accepted.entitlement?.source, GarageEntitlementSource.trial);
    expect(accepted.entitlement?.accessEndsAt,
      DateTime.utc(2026, 10, 25, 8));

    final invalid = <Object?>[
      null,
      <String, Object?>{...activeTrial, 'stripe_subscription_id': 'sub_private'},
      <String, Object?>{...activeTrial, 'active': false},
      <String, Object?>{...activeTrial, 'source': 'active'},
      <String, Object?>{...activeTrial, 'access_ends_at': 'not-a-date'},
      <String, Object?>{...activeTrial}..remove('last_payment_state'),
    ];
    for (final value in invalid) {
      final read = await repository(invoke: (_) async => value).load(workspace);
      expect(read.state, GarageEntitlementReadState.unavailable);
      expect(read.allowsPaidFeatures, isFalse);
    }
  });

  test('cached positive entitlement fails closed at its expiration', () async {
    final now = DateTime.utc(2030, 1, 1, 12);
    final end = now.add(const Duration(seconds: 10));
    final read = GarageEntitlementRead.verified(GarageEntitlement(
      active: true, source: GarageEntitlementSource.trial,
      accessEndsAt: end));
    expect(read.allowsPaidFeaturesAt(now), isTrue);
    expect(read.allowsPaidFeaturesAt(end.subtract(const Duration(microseconds: 1))),
      isTrue);
    expect(read.allowsPaidFeaturesAt(end), isFalse);
    expect(read.allowsPaidFeaturesAt(end.add(const Duration(seconds: 1))),
      isFalse);
    expect(read.allowsPaidFeaturesAt(now.toLocal()), isTrue);
  });

  test('stale server-positive response never authorizes expired access', () async {
    final expiredAt = DateTime.utc(2020, 1, 1);
    final stale = await repository(invoke: (_) async => <String, Object?>{
      'active': true, 'source': 'paid',
      'access_ends_at': expiredAt.toIso8601String(),
      'last_payment_state': 'paid',
    }).load(workspace);
    expect(stale.state, GarageEntitlementReadState.verified);
    expect(stale.entitlement?.active, isTrue);
    expect(stale.allowsPaidFeatures, isFalse);
    expect(stale.allowsPaidFeaturesAt(DateTime.utc(2020, 1, 2)), isFalse);
  });

  test('inactive and unavailable results always deny access at any instant', () {
    final instant = DateTime.utc(2030, 1, 1);
    expect(const GarageEntitlementRead.disabled().allowsPaidFeaturesAt(instant),
      isFalse);
    expect(const GarageEntitlementRead.unavailable().allowsPaidFeaturesAt(instant),
      isFalse);
    expect(GarageEntitlementRead.verified(const GarageEntitlement(
      active: false)).allowsPaidFeaturesAt(instant), isFalse);
    expect(GarageEntitlementRead.verified(GarageEntitlement(
      active: true, source: GarageEntitlementSource.trial,
      accessEndsAt: DateTime.utc(2031))).allowsPaidFeaturesAt(instant), isTrue);
  });

  test('inactive authoritative response remains a verified denial', () async {
    final read = await repository(invoke: (_) async => <String, Object?>{
      'active': false,
      'source': null,
      'access_ends_at': null,
      'last_payment_state': 'failed',
    }).load(workspace);
    expect(read.state, GarageEntitlementReadState.verified);
    expect(read.entitlement?.lastPaymentState, GaragePaymentState.failed);
    expect(read.allowsPaidFeatures, isFalse);
  });

  test('account replacement discards an in-flight positive response', () async {
    var actor = user;
    final read = repository(actor: () => actor, invoke: (_) async {
      actor = '00000000-0000-4000-8000-000000000003';
      return activeTrial;
    });
    expect((await read.load(workspace)).state,
      GarageEntitlementReadState.unavailable);
  });

  test('session replacement discards an in-flight positive result', () async {
    var session = 'first-token';
    final pending = Completer<Object?>();
    var calls = 0;
    final repo = GarageEntitlementRepository(
      enabled: true, supabaseUrl: qa,
      currentUserId: () => user,
      currentSessionKey: () => session,
      invoke: (_) {
        calls++;
        return pending.future;
      },
    );
    final read = repo.load(workspace);
    expect(calls, 1);
    session = 'second-token';
    pending.complete(activeTrial);
    final result = await read;
    expect(result.state, GarageEntitlementReadState.unavailable);
    expect(result.allowsPaidFeatures, isFalse);
  });

  test('signed-out or missing session blocks read without invoking backend', () async {
    String? session;
    var calls = 0;
    final repo = GarageEntitlementRepository(
      enabled: true, supabaseUrl: qa,
      currentUserId: () => user,
      currentSessionKey: () => session,
      invoke: (_) async { calls++; return activeTrial; },
    );
    expect((await repo.load(workspace)).allowsPaidFeatures, isFalse);
    session = '';
    expect((await repo.load(workspace)).allowsPaidFeatures, isFalse);
    expect(calls, 0);
  });

  test('unchanged valid session accepts authoritative response', () async {
    var session = 'session-123';
    final repo = GarageEntitlementRepository(
      enabled: true, supabaseUrl: qa,
      currentUserId: () => user,
      currentSessionKey: () => session,
      invoke: (_) async => activeTrial,
    );
    final read = await repo.load(workspace);
    expect(read.state, GarageEntitlementReadState.verified);
    expect(read.allowsPaidFeaturesAt(DateTime.utc(2026, 10, 20)), isTrue);
    session = 'session-456';
  });

  test('configured factory uses authenticated SDK transport and exact body',
      () async {
    var functionCalls = 0;
    final transport = MockClient((request) async {
      if (request.url.path == '/auth/v1/token') {
        final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
        String part(Object value) => base64Url
            .encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
        final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
            '${part({'sub': user, 'role': 'authenticated', 'exp': expiry})}.fixture';
        return http.Response(jsonEncode({
          'access_token': token,
          'refresh_token': 'fixture-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'expires_at': expiry,
          'user': {
            'id': user,
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'fixture@example.test',
            'created_at': '2026-10-18T00:00:00Z',
            'app_metadata': <String, Object?>{},
            'user_metadata': <String, Object?>{},
          },
        }), 200, request: request,
          headers: {'content-type': 'application/json'});
      }
      expect(request.url.path,
        '/functions/v1/flotaryx-garage-test-entitlement');
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {'workspace_id': workspace});
      expect(request.headers['authorization'], startsWith('Bearer '));
      expect(request.headers['apikey'], 'fixture-publishable-key');
      functionCalls++;
      return http.Response(jsonEncode(activeTrial), 200, request: request,
        headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient(qa, 'fixture-publishable-key',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(() async { await client.dispose(); transport.close(); });

    if (AppConfig.garageSandboxEntitlementEnabled) {
      await client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-only');
      final read = await GarageEntitlementRepository.forClient(client)
        .load(workspace);
      expect(read.allowsPaidFeaturesAt(DateTime.utc(2026, 10, 20)), isTrue);
      expect(functionCalls, 1);
    } else {
      final read = await GarageEntitlementRepository.forClient(client)
        .load(workspace);
      expect(read.state, GarageEntitlementReadState.disabled);
      expect(functionCalls, 0);
    }
  });
}
