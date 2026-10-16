import 'dart:convert';

import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const booking = '00000000-0000-4000-8000-000000000201';
  const user = '00000000-0000-4000-8000-000000000001';
  const accepted = {
    'withdrawn': GarageBookingStatus.withdrawn,
    'cancellation_requested': GarageBookingStatus.cancellationRequested,
    'cancelled': GarageBookingStatus.cancelled,
  };
  for (final result in [...accepted.keys, 'requested', 'confirmed', 'declined', 'unknown']) {
    test('customer cancellation validates RPC result $result', () async {
      var cancellations = 0;
      final transport = MockClient((request) async {
        if (request.url.path == '/auth/v1/token') {
          final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
          String part(Object value) => base64Url
              .encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
          final token = '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
              '${part({'sub': user, 'role': 'authenticated', 'exp': expiry})}.fixture';
          return http.Response(jsonEncode({
            'access_token': token, 'refresh_token': 'fixture-refresh',
            'token_type': 'bearer', 'expires_in': 3600, 'expires_at': expiry,
            'user': {'id': user, 'aud': 'authenticated', 'role': 'authenticated',
              'email': 'fixture@example.test', 'created_at': '2026-10-16T00:00:00Z',
              'app_metadata': {}, 'user_metadata': {}},
          }), 200, request: request, headers: {'content-type': 'application/json'});
        }
        expect(request.url.path, '/rest/v1/rpc/garage_booking_cancel');
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'p_booking': booking});
        cancellations++;
        return http.Response(jsonEncode(result), 200, request: request,
            headers: {'content-type': 'application/json'});
      });
      final client = SupabaseClient('https://fleet-test.invalid', 'test-anon',
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
      addTearDown(() async { await client.dispose(); transport.close(); });
      await client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-only');
      final pending = GarageBookingRepository(client).cancel(booking);
      if (accepted.containsKey(result)) {
        expect(await pending, accepted[result]);
      } else {
        await expectLater(pending, throwsFormatException);
      }
      expect(cancellations, 1);
    });
  }
}
