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
      http.Request? pendingRpcRequest;
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
        pendingRpcRequest = request;
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
      // PostgrestBuilder reads response.request when parsing an RPC. Preserve
      // it in the delayed mock as the synchronous success fixtures already do.
      expect(pendingRpcRequest, isNotNull);
      pendingResponse.complete(http.Response('[]', 200,
          request: pendingRpcRequest,
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
  // Booking submissions also use the session-bound guard. The form retains its
  // original idempotency key when the transport outcome becomes uncertain.
  Future<String> submitBooking(GarageBookingRepository repo) => repo.request(
    workspaceId: workshopId,
    customerName: 'Fixture Customer', vehicleMake: 'Ford',
    vehicleModel: 'Focus', service: 'brakes',
    concern: 'Brake inspection requested',
    desiredStart: DateTime.now().add(const Duration(days: 2)),
    requestKey: '00000000-0000-4000-8000-000000000123',
  );

  test('booking submission without session never reaches the RPC', () async {
    var calls = 0;
    final transport = MockClient((request) async {
      calls++;
      return http.Response('null', 200, request: request,
        headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient('https://fixture.invalid', 'fixture-pub',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(() async { await client.dispose(); transport.close(); });
    await expectLater(submitBooking(GarageBookingRepository(client)),
      throwsStateError);
    expect(calls, 0);
  });

  test('booking submission succeeds with unchanged session and same key',
      () async {
    var logins = 0;
    var requests = 0;
    const id = '00000000-0000-4000-8000-000000000201';
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
      expect(request.url.path, '/rest/v1/rpc/garage_booking_request_once');
      expect(jsonDecode(request.body)['p_request_key'],
          '00000000-0000-4000-8000-000000000123');
      expect(jsonDecode(request.body)['p_workspace'], workshopId);
      requests++;
      return http.Response(jsonEncode(id), 200, request: request,
        headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient('https://fixture.invalid', 'fixture-pub',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(() async { await client.dispose(); transport.close(); });
    await client.auth.signInWithPassword(
      email: 'fixture@example.test', password: 'fixture-only');
    expect(await submitBooking(GarageBookingRepository(client)), id);
    expect(logins, 1);
    expect(requests, 1);
  });

  test('booking submission rejects a replaced same-user session',
      () async {
    var logins = 0;
    var requests = 0;
    const id = '00000000-0000-4000-8000-000000000201';
    final entered = Completer<void>();
    final pendingResponse = Completer<http.Response>();
    http.Request? originalRequest;
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
      expect(request.url.path, '/rest/v1/rpc/garage_booking_request_once');
      expect(jsonDecode(request.body)['p_request_key'],
        '00000000-0000-4000-8000-000000000123');
      originalRequest = request;
      requests++;
      if (!entered.isCompleted) entered.complete();
      return pendingResponse.future;
    });
    final client = SupabaseClient('https://fixture.invalid', 'fixture-pub',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(() async { await client.dispose(); transport.close(); });
    await client.auth.signInWithPassword(
      email: 'fixture@example.test', password: 'fixture-only');
    final originalToken = client.auth.currentSession?.accessToken;
    final pending = submitBooking(GarageBookingRepository(client));
    final denied = expectLater(pending, throwsStateError);
    await entered.future;
    await client.auth.signInWithPassword(
      email: 'fixture@example.test', password: 'fixture-only');
    expect(client.auth.currentUser?.id, userId);
    expect(client.auth.currentSession?.accessToken, isNot(originalToken));
    pendingResponse.complete(http.Response(jsonEncode(id), 200,
      request: originalRequest, headers: {'content-type': 'application/json'}));
    await denied;
    expect(logins, 2);
    expect(requests, 1, reason: 'Do not submit a duplicate booking automatically');
  });

}
