import 'dart:async';
import 'dart:convert';

import 'package:fleetpilot/data/fleet_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final transition in ['unchanged', 'switch', 'logout', 'refresh']) {
    test('membership response is scoped to account after $transition', () async {
      var account = 1;
      final started = Completer<void>();
      late http.Request membershipRequest;
      final response = Completer<http.Response>();
      String userId() => '00000000-0000-4000-8000-00000000000$account';
      final transport = MockClient((request) async {
        if (request.url.path == '/auth/v1/token') {
          final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
          String part(Object value) => base64Url
              .encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
          final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
              '${part({'sub': userId(), 'role': 'authenticated', 'exp': expiry})}.fixture';
          return http.Response(jsonEncode({
            'access_token': token, 'refresh_token': 'fixture-refresh',
            'token_type': 'bearer', 'expires_in': 3600, 'expires_at': expiry,
            'user': {'id': userId(), 'aud': 'authenticated',
              'role': 'authenticated', 'email': 'fixture$account@example.test',
              'created_at': '2026-10-16T00:00:00Z',
              'app_metadata': {}, 'user_metadata': {}},
          }), 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path == '/auth/v1/logout') {
          return http.Response('{}', 200);
        }
        expect(request.url.path, '/rest/v1/company_members');
        expect(request.url.queryParameters['user_id'],
            'eq.00000000-0000-4000-8000-000000000001');
        membershipRequest = request;
        started.complete();
        return response.future;
      });
      final client = SupabaseClient('https://fleet-test.invalid', 'test-anon',
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
      addTearDown(() async { await client.dispose(); transport.close(); });
      Future<void> login() async {
        await client.auth.signInWithPassword(
          email: 'fixture$account@example.test', password: 'fixture-only');
      }
      await login();
      final pending = FleetRepository(client).fetchMemberships();
      await started.future;
      if (transition == 'switch') { account = 2; await login(); }
      if (transition == 'logout') await client.auth.signOut();
      if (transition == 'refresh') await client.auth.refreshSession();
      response.complete(http.Response(jsonEncode([
        {'company_id': 'old-fleet', 'role': 'owner',
          'companies': {'name': 'Original fleet', 'currency': 'GBP'}},
      ]), 200, request: membershipRequest,
          headers: {'content-type': 'application/json'}));
      final memberships = await pending;
      if (transition == 'switch' || transition == 'logout') {
        expect(memberships, isEmpty);
      } else {
        expect(memberships.single.companyId, 'old-fleet');
        expect(memberships.single.role, 'owner');
      }
    });
  }

  test('signed-out membership load makes no transport request', () async {
    var requests = 0;
    final transport = MockClient((_) async {
      requests++;
      throw StateError('Unexpected request');
    });
    final client = SupabaseClient('https://fleet-test.invalid', 'test-anon',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(() async { await client.dispose(); transport.close(); });
    expect(await FleetRepository(client).fetchMemberships(), isEmpty);
    expect(requests, 0);
  });
}
