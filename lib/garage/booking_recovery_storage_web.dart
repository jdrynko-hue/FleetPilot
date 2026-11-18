import 'dart:js_interop';
import 'booking_recovery_journal.dart';

@JS('localStorage')
external _Storage get _storage;

extension type _Storage._(JSObject _) implements JSObject {
  external int get length;
  external JSString? key(int index);
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
  external void removeItem(JSString key);
}

class _BrowserRecoveryStorage implements BookingRecoveryStorage {
  const _BrowserRecoveryStorage();
  @override
  List<String> keys() => [for (var i = 0; i < _storage.length; i++)
    if (_storage.key(i)?.toDart case final String key) key];
  @override
  String? read(String key) => _storage.getItem(key.toJS)?.toDart;
  @override
  void write(String key, String value) => _storage.setItem(key.toJS, value.toJS);
  @override
  void remove(String key) => _storage.removeItem(key.toJS);
}

BookingRecoveryJournal createBookingRecoveryJournal() =>
    const BookingRecoveryJournal(_BrowserRecoveryStorage());
