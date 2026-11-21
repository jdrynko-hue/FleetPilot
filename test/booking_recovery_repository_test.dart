import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fleetpilot/garage/booking_recovery_journal.dart';
import 'package:fleetpilot/garage/consumer_booking_repository.dart';
import 'booking_recovery_journal_test.dart' as fixture;
import 'garage_booking_private_read_scope_test.dart' show fakeJwt;

const booking = '00000000-0000-4000-8000-000000000301';
http.Response reply(http.Request request, Object? body) => http.Response(jsonEncode(body),
  200, request: request, headers: {'content-type': 'application/json'});

Future<SupabaseClient> clientFor(Future<http.Response> Function(http.Request) rpc) async {
  var logins = 0;
  final transport = MockClient((request) async {
    if (request.url.path == '/auth/v1/token') {
      return reply(request, {
        'access_token': fakeJwt(++logins), 'refresh_token': 'fixture-refresh',
        'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': fixture.actor, 'aud': 'authenticated', 'role': 'authenticated',
          'email': 'fixture@example.test', 'created_at': '2026-10-18T00:00:00Z',
          'app_metadata': {}, 'user_metadata': {}},
      });
    }
    return rpc(request);
  });
  final client = SupabaseClient('https://fixture.invalid', 'fixture-pub',
    httpClient: transport, authOptions: const AuthClientOptions(autoRefreshToken: false));
  addTearDown(() async { await client.dispose(); transport.close(); });
  await client.auth.signInWithPassword(email: 'fixture@example.test', password: 'fixture-only');
  return client;
}

Future<String> submit(GarageBookingRepository repository) => repository.request(
  workspaceId: fixture.workshop, requestKey: fixture.requestKey, customerName: 'Private Name',
  vehicleMake: 'Ford', vehicleModel: 'Focus', registration: 'PRIVATE REG', service: 'brakes',
  concern: 'Private concern', desiredStart: DateTime.now().add(const Duration(days: 3)));

Map<String, Object?> recorded({String status = 'requested'}) => {
  'state': 'recorded', 'request_key': fixture.requestKey, 'booking_id': booking,
  'workspace_id': fixture.workshop, 'status': status,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('marker is verified before POST and removed only after validated success', () async {
    final storage = fixture.TestRecoveryStorage();
    final journal = BookingRecoveryJournal(storage);
    var calls = 0;
    final client = await clientFor((request) async {
      calls++;
      expect(request.url.path, '/rest/v1/rpc/garage_booking_request_once');
      expect(journal.pending(fixture.actor).single.requestKey, fixture.requestKey);
      final saved = storage.data.values.single;
      for (final secret in ['Private Name', 'PRIVATE REG', 'Private concern', 'access_token']) {
        expect(saved, isNot(contains(secret)));
      }
      return reply(request, booking);
    });
    expect(await submit(GarageBookingRepository(client, recoveryJournal: journal)), booking);
    expect(calls, 1);
    expect(journal.pending(fixture.actor), isEmpty);
  });

  test('lost response survives reconstruction and resolves terminal status without replay', () async {
    final storage = fixture.TestRecoveryStorage();
    var writes = 0, resolutions = 0;
    final client = await clientFor((request) async {
      if (request.url.path.endsWith('/garage_booking_request_once')) {
        writes++;
        throw TimeoutException('Synthetic lost response');
      }
      expect(request.url.path, '/rest/v1/rpc/garage_booking_resolve_request');
      expect(jsonDecode(request.body), {'p_request_key': fixture.requestKey});
      resolutions++;
      return reply(request, recorded(status: 'declined'));
    });
    final first = GarageBookingRepository(client, recoveryJournal: BookingRecoveryJournal(storage));
    await expectLater(submit(first), throwsA(isA<TimeoutException>()));
    final restored = GarageBookingRepository(client, recoveryJournal: BookingRecoveryJournal(storage));
    expect(restored.pendingRequests(), hasLength(1));
    final result = await restored.resolvePendingRequest(restored.pendingRequests().single);
    expect(result.bookingId, booking);
    expect(result.status, GarageBookingStatus.declined);
    expect(restored.pendingRequests(), isEmpty);
    expect(writes, 1);
    expect(resolutions, 1);
  });

  test('storage failure and existing unresolved attempt both block POST', () async {
    var calls = 0;
    final client = await clientFor((request) async { calls++; return reply(request, booking); });
    final storage = fixture.TestRecoveryStorage()..denyWrite = true;
    final journal = BookingRecoveryJournal(storage);
    final repository = GarageBookingRepository(client, recoveryJournal: journal);
    await expectLater(submit(repository), throwsA(isA<BookingRecoveryUnavailable>()));
    expect(calls, 0);
    storage.denyWrite = false;
    journal.begin(actor: fixture.actor, workspace: fixture.workshop, requestKey: fixture.secondKey);
    await expectLater(submit(repository), throwsA(isA<BookingRecoveryPending>()));
    expect(calls, 0);
  });

  test('not_received clears the marker without submitting a new request', () async {
    final journal = BookingRecoveryJournal(fixture.TestRecoveryStorage());
    final marker = journal.begin(actor: fixture.actor, workspace: fixture.workshop,
      requestKey: fixture.requestKey);
    var calls = 0;
    final client = await clientFor((request) async {
      calls++;
      expect(request.url.path, '/rest/v1/rpc/garage_booking_resolve_request');
      return reply(request, {'state': 'not_received', 'request_key': fixture.requestKey,
        'booking_id': null, 'workspace_id': null, 'status': null});
    });
    final result = await GarageBookingRepository(client, recoveryJournal: journal).resolvePendingRequest(marker);
    expect(result.wasRecorded, isFalse);
    expect(journal.pending(fixture.actor), isEmpty);
    expect(calls, 1);
  });

  test('a replaced session cannot clear the journal with its late resolution', () async {
    final journal = BookingRecoveryJournal(fixture.TestRecoveryStorage());
    final marker = journal.begin(actor: fixture.actor, workspace: fixture.workshop,
      requestKey: fixture.requestKey);
    final entered = Completer<http.Request>();
    final response = Completer<http.Response>();
    final client = await clientFor((request) { entered.complete(request); return response.future; });
    final repository = GarageBookingRepository(client, recoveryJournal: journal);
    final pending = repository.resolvePendingRequest(marker);
    final denied = expectLater(pending, throwsStateError);
    final request = await entered.future;
    await client.auth.signInWithPassword(email: 'fixture@example.test', password: 'fixture-only');
    response.complete(reply(request, recorded()));
    await denied;
    expect(journal.pending(fixture.actor), hasLength(1));
  });

  test('other account marker is rejected before making any private RPC', () async {
    var calls = 0;
    final client = await clientFor((request) async { calls++; return reply(request, recorded()); });
    final journal = BookingRecoveryJournal(fixture.TestRecoveryStorage());
    final marker = journal.begin(actor: fixture.otherActor, workspace: fixture.workshop,
      requestKey: fixture.requestKey);
    await expectLater(GarageBookingRepository(client, recoveryJournal: journal)
      .resolvePendingRequest(marker), throwsStateError);
    expect(calls, 0);
    expect(journal.pending(fixture.otherActor), hasLength(1));
  });

  for (final bad in [
    [], {...recorded(), 'request_key': fixture.secondKey},
    {...recorded(), 'workspace_id': fixture.otherActor},
    {...recorded(), 'status': 'unknown'}, {...recorded(), 'booking_id': null},
    {'state': 'not_received', 'request_key': fixture.requestKey},
  ]) {
    test('malformed recovery response keeps the original marker: $bad', () async {
      final journal = BookingRecoveryJournal(fixture.TestRecoveryStorage());
      final marker = journal.begin(actor: fixture.actor, workspace: fixture.workshop,
        requestKey: fixture.requestKey);
      final client = await clientFor((request) async => reply(request, bad));
      await expectLater(GarageBookingRepository(client, recoveryJournal: journal)
        .resolvePendingRequest(marker), throwsFormatException);
      expect(journal.pending(fixture.actor), hasLength(1));
    });
  }
}
