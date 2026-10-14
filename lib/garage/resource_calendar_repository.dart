import 'package:supabase_flutter/supabase_flutter.dart';

/// Private Garage calendar adapter. Database RPCs independently authorize
/// current workshop roles and enforce resource capacity/availability.
/// Deliberately NOT connected to production Fleet navigation.
class GarageResourceCalendarRepository {
  const GarageResourceCalendarRepository(this.client);

  final SupabaseClient client;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String validatedId(String id) {
    if (!_uuid.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Valid UUID required');
    }
    return id;
  }

  void _signedIn() {
    if (client.auth.currentUser == null) {
      throw StateError('Sign in to manage your workshop bookings');
    }
  }

  static String _text(Map row, String key) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid calendar $key');
    }
    return value;
  }

  static String _rowId(Map row, String key) {
    final id = _text(row, key);
    if (!_uuid.hasMatch(id)) throw FormatException('Invalid calendar $key');
    return id;
  }

  static String? _optionalId(Map row, String key) {
    if (row[key] == null) return null;
    return _rowId(row, key);
  }

  static DateTime _timestamp(Map row, String key) {
    final date = DateTime.tryParse(_text(row, key));
    if (date == null) throw FormatException('Invalid calendar $key');
    return date.toUtc();
  }

  static List<T> _list<T>(Object? data, T Function(Map) parse,
      {int max = 500}) {
    if (data is! List || data.length > max) {
      throw const FormatException('Invalid calendar response size');
    }
    return List<T>.unmodifiable(data.map((row) {
      if (row is! Map) throw const FormatException('Invalid calendar row');
      return parse(row);
    }));
  }

  static List<GarageCalendarResource> parseResources(Object? data) =>
      _list(data, (row) {
        if (row['active'] is! bool) {
          throw const FormatException('Invalid resource active state');
        }
        return GarageCalendarResource(
          id: _rowId(row, 'id'),
          name: _text(row, 'display_name'),
          mechanicUserId: _optionalId(row, 'mechanic_user_id'),
          active: row['active'] as bool,
        );
      });

  static List<GarageOpeningHours> parseHours(Object? data) =>
      _list(data, (row) {
        final day = row['iso_weekday'];
        final start = _text(row, 'opens_at');
        final end = _text(row, 'closes_at');
        if (day is! int || day < 1 || day > 7 ||
            !_validTime(start) || !_validTime(end) ||
            start.compareTo(end) >= 0) {
          throw const FormatException('Invalid opening hours');
        }
        return GarageOpeningHours(
          isoWeekday: day, opensAt: start, closesAt: end,
        );
      }, max: 7);

  static bool _validTime(String input) => RegExp(
    r'^(?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9](?:\.[0-9]+)?)?$',
  ).hasMatch(input);

  static List<GarageCalendarAppointment> parseCalendar(Object? data) =>
      _list(data, (row) {
        final minutes = row['duration_minutes'];
        final status = _text(row, 'status');
        if (minutes is! int || !const {30, 60, 90, 120}.contains(minutes) ||
            !const {'confirmed', 'cancellation_requested'}.contains(status)) {
          throw const FormatException('Invalid calendar appointment status');
        }
        final resourceId = _optionalId(row, 'resource_id');
        final resourceName = row['resource_name'];
        if (resourceName != null && resourceName is! String) {
          throw const FormatException('Invalid calendar bay name');
        }
        return GarageCalendarAppointment(
          bookingId: _rowId(row, 'booking_id'),
          resourceId: resourceId,
          resourceName: resourceName as String?,
          startAt: _timestamp(row, 'start_at'),
          durationMinutes: minutes,
          status: status,
          customerName: _text(row, 'customer_name'),
        );
      });

  static List<GarageBookingNotice> parseNotifications(Object? data) =>
      _list(data, (row) {
        final action = _text(row, 'event_action');
        if (!const {
          'requested', 'confirmed', 'declined', 'withdrawn',
          'cancellation_requested', 'cancelled',
        }.contains(action)) {
          throw const FormatException('Unknown booking notification event');
        }
        final readAt = row['read_at'];
        final read = readAt == null ? null : DateTime.tryParse(
            readAt is String ? readAt : '');
        if (readAt != null && read == null) {
          throw const FormatException('Invalid notification read time');
        }
        return GarageBookingNotice(
          id: _rowId(row, 'id'),
          bookingId: _rowId(row, 'booking_id'),
          event: action,
          occurredAt: _timestamp(row, 'occurred_at'),
          readAt: read?.toUtc(),
        );
      }, max: 50);

  Future<List<GarageCalendarResource>> resources(String shopId) async {
    _signedIn();
    return parseResources(await client.rpc('garage_booking_resource_list',
      params: {'p_shop': validatedId(shopId)}));
  }

  Future<List<GarageOpeningHours>> openingHours(String shopId) async {
    _signedIn();
    return parseHours(await client.rpc('garage_booking_hours_list',
      params: {'p_shop': validatedId(shopId)}));
  }

  Future<bool> setHours({
    required String shopId,
    required int weekday,
    required String opensAt,
    required String closesAt,
    required bool enabled,
  }) async {
    _signedIn();
    validatedId(shopId);
    if (weekday < 1 || weekday > 7 ||
        (enabled && (!_validTime(opensAt) || !_validTime(closesAt) ||
                     opensAt.compareTo(closesAt) >= 0))) {
      throw ArgumentError('Invalid workshop hours');
    }
    final result = await client.rpc('garage_booking_set_hours', params: {
      'p_shop': shopId,
      'p_day': weekday,
      'p_opens': enabled ? opensAt : null,
      'p_closes': enabled ? closesAt : null,
      'p_enabled': enabled,
    });
    if (result != true) throw const FormatException('Hours update unconfirmed');
    return true;
  }

  Future<String> addResource({
    required String shopId,
    required String name,
    String? mechanicUserId,
  }) async {
    _signedIn();
    validatedId(shopId);
    if (name.trim().length < 2 || name.length > 70) {
      throw ArgumentError.value(name, 'name');
    }
    if (mechanicUserId != null) validatedId(mechanicUserId);
    final response = await client.rpc('garage_booking_add_resource', params: {
      'p_shop': shopId,
      'p_label': name.trim(),
      'p_mechanic': mechanicUserId,
    });
    if (response is! String || !_uuid.hasMatch(response)) {
      throw const FormatException('Invalid created resource ID');
    }
    return response;
  }

  Future<bool> setResourceActive({
    required String shopId, required String resourceId,
    required bool active,
  }) async {
    _signedIn();
    final response = await client.rpc('garage_booking_resource_active', params: {
      'p_shop': validatedId(shopId),
      'p_resource': validatedId(resourceId),
      'p_active': active,
    });
    if (response != true) {
      throw const FormatException('Resource state was not confirmed');
    }
    return true;
  }

  Future<String> confirmBooking(String bookingId, String resourceId) async {
    _signedIn();
    final response = await client.rpc('garage_booking_confirm_slot', params: {
      'p_booking': validatedId(bookingId),
      'p_resource': validatedId(resourceId),
    });
    if (response != 'confirmed') {
      throw const FormatException('Booking time not confirmed by the server');
    }
    return 'confirmed';
  }

  Future<List<GarageCalendarAppointment>> calendar({
    required String shopId, required DateTime start, required DateTime end,
  }) async {
    _signedIn();
    validatedId(shopId);
    if (!end.isAfter(start) ||
        end.difference(start) > const Duration(days: 15)) {
      throw ArgumentError('Calendar window must be at most 15 days');
    }
    return parseCalendar(await client.rpc('garage_booking_calendar', params: {
      'p_shop': shopId,
      'p_from': start.toUtc().toIso8601String(),
      'p_until': end.toUtc().toIso8601String(),
    }));
  }

  Future<List<GarageBookingNotice>> notifications() async {
    _signedIn();
    return parseNotifications(await client.rpc('garage_booking_my_notifications'));
  }

  Future<bool> acknowledge(String noticeId) async {
    _signedIn();
    final response = await client.rpc('garage_booking_mark_notification_read',
      params: {'p_id': validatedId(noticeId)});
    if (response != true) {
      throw const FormatException('Notification read not confirmed');
    }
    return true;
  }
}

class GarageCalendarResource {
  const GarageCalendarResource({
    required this.id, required this.name,
    required this.active, this.mechanicUserId,
  });
  final String id;
  final String name;
  final bool active;
  final String? mechanicUserId;
}

class GarageOpeningHours {
  const GarageOpeningHours({
    required this.isoWeekday, required this.opensAt, required this.closesAt,
  });
  final int isoWeekday;
  final String opensAt;
  final String closesAt;
}

class GarageCalendarAppointment {
  const GarageCalendarAppointment({
    required this.bookingId, required this.resourceId,
    required this.resourceName, required this.startAt,
    required this.durationMinutes, required this.status,
    required this.customerName,
  });
  final String bookingId;
  final String? resourceId;
  final String? resourceName;
  final DateTime startAt;
  final int durationMinutes;
  final String status;
  final String customerName;
  bool get holdsCapacity => status == 'confirmed' ||
      status == 'cancellation_requested';
}

class GarageBookingNotice {
  const GarageBookingNotice({
    required this.id, required this.bookingId, required this.event,
    required this.occurredAt, this.readAt,
  });
  final String id;
  final String bookingId;
  final String event;
  final DateTime occurredAt;
  final DateTime? readAt;
  bool get unread => readAt == null;
}
