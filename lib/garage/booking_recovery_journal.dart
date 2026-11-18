import 'dart:convert';

/// Only opaque identifiers are persisted. No form fields or session tokens.
class PendingBookingRequest {
  const PendingBookingRequest({required this.actorId, required this.workspaceId,
    required this.requestKey, required this.createdAt});
  final String actorId;
  final String workspaceId;
  final String requestKey;
  final DateTime createdAt;

  String encode() => jsonEncode({'version': 1, 'actor': actorId,
    'workspace': workspaceId, 'request': requestKey,
    'created': createdAt.toUtc().toIso8601String()});

  static PendingBookingRequest decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map || value.length != 5 || value['version'] != 1 ||
        !validBookingRecoveryId(value['actor']) ||
        !validBookingRecoveryId(value['workspace']) ||
        !validBookingRecoveryId(value['request']) || value['created'] is! String) {
      throw const FormatException('Invalid booking recovery marker');
    }
    final created = DateTime.tryParse(value['created'] as String);
    if (created == null || !created.isUtc) {
      throw const FormatException('Invalid booking recovery timestamp');
    }
    return PendingBookingRequest(actorId: value['actor'] as String,
      workspaceId: value['workspace'] as String, requestKey: value['request'] as String,
      createdAt: created);
  }
}

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
    r'[0-9a-f]{4}-[0-9a-f]{12}$');
bool validBookingRecoveryId(Object? value) => value is String && _uuid.hasMatch(value);

abstract interface class BookingRecoveryStorage {
  List<String> keys();
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

/// This exception is only emitted BEFORE the network mutation starts.
class BookingRecoveryUnavailable implements Exception {
  const BookingRecoveryUnavailable();
}

class BookingRecoveryPending implements Exception {
  const BookingRecoveryPending();
}

class BookingRecoveryJournal {
  const BookingRecoveryJournal(this.storage);
  final BookingRecoveryStorage storage;
  static const prefix = 'flotaryx.booking.pending.v1.';
  String _actorPrefix(String actor) {
    if (!validBookingRecoveryId(actor)) throw ArgumentError('Invalid recovery actor');
    return '$prefix$actor.';
  }
  String _key(PendingBookingRequest entry) => '${_actorPrefix(entry.actorId)}${entry.requestKey}';

  List<PendingBookingRequest> pending(String actor) {
    final scope = _actorPrefix(actor);
    final keys = storage.keys().where((key) => key.startsWith(scope)).toList();
    if (keys.length > 100) throw StateError('Too many pending booking attempts');
    final result = <PendingBookingRequest>[];
    for (final key in keys) {
      final raw = storage.read(key);
      if (raw == null) continue; // Another tab may have resolved it.
      final entry = PendingBookingRequest.decode(raw);
      if (entry.actorId != actor || _key(entry) != key) {
        throw const FormatException('Booking recovery scope mismatch');
      }
      result.add(entry);
    }
    // No automatic expiry: an old request may still have been accepted.
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(result);
  }

  PendingBookingRequest begin({required String actor, required String workspace,
      required String requestKey}) {
    try {
      if (!validBookingRecoveryId(workspace) || !validBookingRecoveryId(requestKey)) {
        throw ArgumentError('Invalid booking recovery scope');
      }
      if (pending(actor).isNotEmpty) throw const BookingRecoveryPending();
      final entry = PendingBookingRequest(actorId: actor, workspaceId: workspace,
        requestKey: requestKey, createdAt: DateTime.now().toUtc());
      final raw = entry.encode();
      // Separate keys ensure competing tabs cannot overwrite another attempt.
      storage.write(_key(entry), raw);
      if (storage.read(_key(entry)) != raw) throw StateError('Recovery write failed');
      return entry;
    } on BookingRecoveryPending {
      rethrow;
    } catch (_) {
      throw const BookingRecoveryUnavailable();
    }
  }

  void complete(PendingBookingRequest entry) {
    final key = _key(entry);
    if (storage.read(key) != entry.encode()) return;
    storage.remove(key);
    if (storage.read(key) != null) throw StateError('Recovery removal failed');
  }
}
