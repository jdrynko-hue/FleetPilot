// Run explicitly with --platform chrome. Uses real browser localStorage.
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/booking_recovery_journal.dart';
import 'package:fleetpilot/garage/booking_recovery_storage_web.dart';

void main() {
  test('real browser storage preserves opaque attempts across journal lifetimes', () {
    const actor = '00000000-0000-4000-8000-000000000991';
    const other = '00000000-0000-4000-8000-000000000992';
    const workspace = '00000000-0000-4000-8000-000000000993';
    const key = '00000000-0000-4000-8000-000000000994';
    final first = createBookingRecoveryJournal();
    void cleanup() {
      for (final storageKey in first.storage.keys().where((key) =>
          key.startsWith('${BookingRecoveryJournal.prefix}$actor.') ||
          key.startsWith('${BookingRecoveryJournal.prefix}$other.'))) {
        first.storage.remove(storageKey);
      }
    }
    cleanup();
    addTearDown(cleanup);
    final marker = first.begin(actor: actor, workspace: workspace, requestKey: key);
    final restored = createBookingRecoveryJournal();
    expect(restored.pending(actor).single.encode(), marker.encode());
    expect(restored.pending(other), isEmpty);
    expect(() => restored.begin(actor: actor, workspace: workspace, requestKey: key),
      throwsA(isA<BookingRecoveryPending>()));
    restored.complete(marker);
    expect(createBookingRecoveryJournal().pending(actor), isEmpty);
  });
}
