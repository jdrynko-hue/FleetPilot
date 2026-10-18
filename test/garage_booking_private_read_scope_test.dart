import 'dart:async';
import 'dart:convert';

import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const userId = '00000000-0000-4000-8000-000000000001';
const workshopId = '00000000-0000-4000-8000-000000000101';

String fakeJwt(int version) {
  String part(Object value) => base64Url
      .encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expires = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': userId, 'role': 'authenticated',
                'exp': expires, 'version': version})}.fixture';
}

Future<dynamic> privateRead(GarageBookingRepository repository, String path) =>
    switch (path) {
      'garage_booking_my_requests' => repository.myRequests(),
      'garage_booking_shop_inbox' => repository.workshopInbox(workshopId),
      'garage_booking_profile' => repository.profile(workshopId),
      _ => throw ArgumentError('Unexpected test RPC'),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = [
    'garage_booking_my_requests',
    'garage_booking_shop_inbox',
    'garage_booking_profile',
  ];

  for (final path in paths) {
    test('$path requires a signed-in session before private RPC', () async {
      var rpcCalls = 0;
      final transport = MockClient((request) async {
        rpcCalls++;
        return http.Response('[]', 200, request: request,
            headers: {'content-type': 'application/json'});
      });
      final client = SupabaseClient('https://fixture.invalid', 'fixture-pub',
          httpClient: transport,
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      addTearDown(() async { await client.dispose(); transport.close(); });
      await expectLater(privateRead(GarageBookingRepository(client), path),
          throwsStateError);
      expect(rpcCalls, 0);
    });

    test('$path drops private rows after same-user session replacement',
        () async {
      var logins = 0;
      var rpcCalls = 0;
      final enteredRpc = Completer<void>();
      final pendingResponse = Completer<http.Response>();
      final transport = MockClient((request) async {
        if (request.url.path == '/auth/v1/token') {
          logins++;
          final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
          return http.Response(jsonEncode({
            'access_token': fakeJwt(logins), 'refresh_token': 'fixture-refresh',
            'token_type': 'bearer', 'expires_in': 3600, 'expires_at': expiry,
            'user': {
              'id': userId, 'aud': 'authenticated', 'role': 'authenticated',
              'email': 'fixture@example.test',
              'created_at': '2026-10-18T00:00:00Z',
              'app_metadata': {}, 'user_metadata': {},
            },
          }), 200, request: request,
              headers: {'content-type': 'application/json'});
        }
        expect(request.url.path, '/rest/v1/rpc/$path');
        rpcCalls++;
        if (!enteredRpc.isCompleted) enteredRpc.complete();
        return pendingResponse.future;
      });
      final client = SupabaseClient('https://fixture.invalid', 'fixture-pub',
          httpClient: transport,
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      addTearDown(() async { await client.dispose(); transport.close(); });
      await client.auth.signInWithPassword(
          email: 'fixture@example.test', password: 'fixture-only');
      final tokenBefore = client.auth.currentSession?.accessToken;
      final read = privateRead(GarageBookingRepository(client), path);
      // Attach the exception matcher before resolving the pending request.
      final denied = expectLater(read, throwsStateError);
      await enteredRpc.future;
      await client.auth.signInWithPassword(
          email: 'fixture@example.test', password: 'fixture-only');
      expect(client.auth.currentUser?.id, userId);
      expect(client.auth.currentSession?.accessToken, isNot(tokenBefore));
      pendingResponse.complete(http.Response('[]', 200,
          headers: {'content-type': 'application/json'}));
      await denied;
      expect(logins, 2);
      expect(rpcCalls, 1);
    });

    test('$path accepts empty private result under an unchanged session',
        () async {
      var rpcCalls = 0;
      final transport = MockClient((request) async {
        if (request.url.path == '/auth/v1/token') {
          final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
          return http.Response(jsonEncode({
            'access_token': fakeJwt(1), 'refresh_token': 'fixture-refresh',
            'token_type': 'bearer', 'expires_in': 3600, 'expires_at': expiry,
            'user': {
              'id': userId, 'aud': 'authenticated', 'role': 'authenticated',
              'email': 'fixture@example.test',
              'created_at': '2026-10-18T00:00:00Z',
              'app_metadata': {}, 'user_metadata': {},
            },
          }), 200, request: request,
              headers: {'content-type': 'application/json'});
        }
        expect(request.url.path, '/rest/v1/rpc/$path');
        rpcCalls++;
        return http.Response('[]', 200, request: request,
            headers: {'content-type': 'application/json'});
      });
      final client = SupabaseClient('https://fixture.invalid', 'fixture-pub',
          httpClient: transport,
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      addTearDown(() async { await client.dispose(); transport.close(); });
      await client.auth.signInWithPassword(
          email: 'fixture@example.test', password: 'fixture-only');
      final result = await privateRead(GarageBookingRepository(client), path);
      if (path == 'garage_booking_profile') {
        expect(result, isNull);
      } else {
        expect(result, isEmpty);
      }
      expect(rpcCalls, 1);
    });
  }
}
