import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/booking_recovery_journal.dart';

const actor = '00000000-0000-4000-8000-000000000001';
const otherActor = '00000000-0000-4000-8000-000000000002';
const workshop = '00000000-0000-4000-8000-000000000101';
const requestKey = '00000000-0000-4000-8000-000000000201';
const secondKey = '00000000-0000-4000-8000-000000000202';

class TestRecoveryStorage implements BookingRecoveryStorage {
  final data = <String, String>{};
  bool denyRead = false, denyWrite = false, denyRemove = false, ignoreWrite = false;
  @override
  List<String> keys() {
    if (denyRead) throw StateError('Synthetic storage restriction');
    return data.keys.toList();
  }
  @override
  String? read(String key) {
    if (denyRead) throw StateError('Synthetic storage restriction');
    return data[key];
  }
  @override
  void write(String key, String value) {
    if (denyWrite) throw StateError('Synthetic quota restriction');
    if (!ignoreWrite) data[key] = value;
  }
  @override
  void remove(String key) {
    if (denyRemove) throw StateError('Synthetic removal restriction');
    data.remove(key);
  }
}

void main() {
  test('new repository/screen lifetime recovers only opaque markers for its account', () {
    final storage = TestRecoveryStorage();
    final first = BookingRecoveryJournal(storage);
    final marker = first.begin(actor: actor, workspace: workshop, requestKey: requestKey);
    first.begin(actor: otherActor, workspace: workshop, requestKey: requestKey);
    final restored = BookingRecoveryJournal(storage);
    expect(restored.pending(actor).single.encode(), marker.encode());
    expect(restored.pending(otherActor).single.actorId, otherActor);
    expect(jsonDecode(storage.data.values.first).keys.toSet(),
      {'version', 'actor', 'workspace', 'request', 'created'});
    expect(() => restored.begin(actor: actor, workspace: workshop, requestKey: secondKey),
      throwsA(isA<BookingRecoveryPending>()));
    restored.complete(marker);
    expect(restored.pending(actor), isEmpty);
    expect(restored.pending(otherActor), hasLength(1));
  });

  test('competing tabs retain separate keys and clearing one cannot erase another', () {
    final storage = TestRecoveryStorage();
    final journal = BookingRecoveryJournal(storage);
    final first = journal.begin(actor: actor, workspace: workshop, requestKey: requestKey);
    final second = PendingBookingRequest(actorId: actor, workspaceId: workshop,
      requestKey: secondKey, createdAt: first.createdAt.add(const Duration(seconds: 1)));
    storage.write('${BookingRecoveryJournal.prefix}$actor.$secondKey', second.encode());
    expect(journal.pending(actor), hasLength(2));
    journal.complete(first);
    expect(journal.pending(actor).single.requestKey, secondKey);
    journal.complete(first); // A stale completion is harmless.
    expect(journal.pending(actor).single.requestKey, secondKey);
  });

  test('pending markers never expire into an automatic new attempt', () {
    final storage = TestRecoveryStorage();
    final old = PendingBookingRequest(actorId: actor, workspaceId: workshop,
      requestKey: requestKey, createdAt: DateTime.utc(2020));
    storage.write('${BookingRecoveryJournal.prefix}$actor.$requestKey', old.encode());
    expect(BookingRecoveryJournal(storage).pending(actor).single.createdAt, DateTime.utc(2020));
  });

  test('corrupt or mismatched markers fail closed instead of disappearing', () {
    for (final raw in ['broken', '{}', jsonEncode({'version': 2}),
      PendingBookingRequest(actorId: otherActor, workspaceId: workshop,
        requestKey: requestKey, createdAt: DateTime.utc(2026)).encode()]) {
      final storage = TestRecoveryStorage();
      storage.write('${BookingRecoveryJournal.prefix}$actor.$requestKey', raw);
      expect(() => BookingRecoveryJournal(storage).pending(actor), throwsFormatException);
      expect(storage.data, hasLength(1));
    }
  });

  test('blocked, full or silently ignored storage refuses a network intent', () {
    for (final mode in ['read', 'write', 'ignore']) {
      final storage = TestRecoveryStorage()
        ..denyRead = mode == 'read' ..denyWrite = mode == 'write' ..ignoreWrite = mode == 'ignore';
      expect(() => BookingRecoveryJournal(storage).begin(actor: actor,
        workspace: workshop, requestKey: requestKey), throwsA(isA<BookingRecoveryUnavailable>()));
    }
  });

  test('failed cleanup retains the unresolved marker', () {
    final storage = TestRecoveryStorage();
    final journal = BookingRecoveryJournal(storage);
    final marker = journal.begin(actor: actor, workspace: workshop, requestKey: requestKey);
    storage.denyRemove = true;
    expect(() => journal.complete(marker), throwsStateError);
    expect(journal.pending(actor), hasLength(1));
  });
}
