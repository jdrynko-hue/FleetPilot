import 'dart:async';
import 'dart:convert';

import 'package:fleetpilot/company/operator_session_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = '00000000-0000-4000-8000-000000000001';

String _fakeJwt(int version) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _userId, 'role': 'authenticated', 'exp': expiry,
                'version': version})}.fixture';
}

http.Response _loginResponse(http.Request request, int version) {
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  return http.Response(jsonEncode({
    'access_token': _fakeJwt(version),
    'refresh_token': 'fixture-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': expiry,
    'user': {
      'id': _userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'fixture@example.test',
      'created_at': '2026-10-18T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {},
    },
  }), 200, request: request,
      headers: {'content-type': 'application/json'});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('signed-out operator RPC is never invoked', () async {
    var transportCalls = 0;
    final transport = MockClient((request) async {
      transportCalls++;
      return http.Response('[]', 200, request: request,
          headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient('https://fixture.invalid', 'fixture-pub',
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(() async { await client.dispose(); transport.close(); });
    var actionCalls = 0;
    await expectLater(OperatorSessionGuard(client).run(() async {
      actionCalls++;
      return true;
    }), throwsStateError);
    expect(actionCalls, 0);
    expect(transportCalls, 0);
  });

  test('stable authenticated session accepts operator response', () async {
    var logins = 0;
    final transport = MockClient((request) async {
      expect(request.url.path, '/auth/v1/token');
      logins++;
      return _loginResponse(request, logins);
    });
    final client = SupabaseClient('https://fixture.invalid', 'fixture-pub',
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(() async { await client.dispose(); transport.close(); });
    await client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-only');
    final result = await OperatorSessionGuard(client).run(() async => 42);
    expect(result, 42);
    expect(logins, 1);
  });

  test('same-user session rotation discards deferred operator result',
      () async {
    var logins = 0;
    var actions = 0;
    final transport = MockClient((request) async {
      expect(request.url.path, '/auth/v1/token');
      logins++;
      return _loginResponse(request, logins);
    });
    final client = SupabaseClient('https://fixture.invalid', 'fixture-pub',
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(() async { await client.dispose(); transport.close(); });
    await client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-only');
    final tokenBefore = client.auth.currentSession?.accessToken;
    final delayed = Completer<int>();
    final pending = OperatorSessionGuard(client).run(() {
      actions++;
      return delayed.future;
    });
    final denied = expectLater(pending, throwsStateError);
    await client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-only');
    expect(client.auth.currentUser?.id, _userId);
    expect(client.auth.currentSession?.accessToken, isNot(tokenBefore));
    delayed.complete(42);
    await denied;
    expect(logins, 2);
    expect(actions, 1, reason: 'Privileged mutations must not auto-retry');
  });
}
