import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

/// One random key per form intent; never reused across account/workshop scopes.
String newBookingRequestKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Garage consumer booking is a workshop-reviewed preference, not an instant
/// confirmed reservation. Staging only: do not link public navigation before
/// the Garage schema, tenant-isolation QA and launch approval are complete.
enum GarageBookingStatus {
  requested,
  confirmed,
  declined,
  withdrawn,
  cancellationRequested,
  cancelled,
}

class GarageBookingProfile {
  const GarageBookingProfile({required this.workspaceId, required this.city,
    required this.timeZone, required this.services, required this.durationMinutes,
    required this.listed});
  final String workspaceId;
  final String city;
  final String timeZone;
  final List<String> services;
  final int durationMinutes;
  final bool listed;
}

class GarageBookingService {
  static const values = {
    'diagnostics',
    'maintenance',
    'brakes',
    'tyres',
    'inspection',
    'electrical',
    'bodywork',
    'other',
  };
}

class GarageBookingWorkshop {
  const GarageBookingWorkshop({
    required this.workspaceId,
    required this.name,
    required this.city,
    required this.country,
    required this.timeZone,
    required this.services,
  });

  final String workspaceId;
  final String name;
  final String city;
  final String country;
  final String timeZone;
  final List<String> services;
}

class GarageBookingSummary {
  const GarageBookingSummary({
    required this.id,
    required this.workspaceId,
    required this.workshopName,
    required this.startAt,
    required this.status,
    required this.service,
    this.workOrderId,
  });

  final String id;
  final String workspaceId;
  final String workshopName;
  final DateTime startAt;
  final GarageBookingStatus status;
  final String service;
  final String? workOrderId;

  bool get isConfirmed => status == GarageBookingStatus.confirmed;
  bool get isOnlyRequested => status == GarageBookingStatus.requested;
}

class GarageBookingInboxItem {
  const GarageBookingInboxItem({
    required this.id,
    required this.customerName,
    required this.customerEmail,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.service,
    required this.concern,
    required this.startAt,
    required this.durationMinutes,
    required this.status,
    this.registration,
  });

  final String id;
  final String customerName;
  final String customerEmail;
  final String vehicleMake;
  final String vehicleModel;
  final String? registration;
  final String service;
  final String concern;
  final DateTime startAt;
  final int durationMinutes;
  final GarageBookingStatus status;
}

/// Every privileged API independently checks auth.uid and workspace roles.
/// Raw Garage booking tables cannot be read or written by client credentials.
class GarageBookingRepository {
  const GarageBookingRepository(this.client);

  final SupabaseClient client;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String _id(String id) {
    if (!_uuid.hasMatch(id)) throw ArgumentError.value(id, 'id', 'UUID required');
    return id;
  }

  void _requireSignIn() {
    if (client.auth.currentUser == null) {
      throw StateError('A verified customer or Garage account must be signed in');
    }
  }

  // A private read started under one session must never render after another
  // account/login takes over the same client (even with the same user ID).
  // Compare the token only in memory. No token is logged or sent elsewhere.
  Future<T> _privateRead<T>(Future<T> Function() request) async {
    _requireSignIn();
    final actor = client.auth.currentUser!.id;
    final sessionKey = client.auth.currentSession?.accessToken;
    if (sessionKey == null || sessionKey.isEmpty) {
      throw StateError('Authenticated booking session required');
    }
    final result = await request();
    if (client.auth.currentUser?.id != actor ||
        client.auth.currentSession?.accessToken != sessionKey) {
      throw StateError('Booking session changed during read');
    }
    return result;
  }

  static GarageBookingStatus _status(Object? raw) => switch (raw) {
    'requested' => GarageBookingStatus.requested,
    'confirmed' => GarageBookingStatus.confirmed,
    'declined' => GarageBookingStatus.declined,
    'withdrawn' => GarageBookingStatus.withdrawn,
    'cancellation_requested' => GarageBookingStatus.cancellationRequested,
    'cancelled' => GarageBookingStatus.cancelled,
    _ => throw const FormatException('Unknown booking status'),
  };

  static String _text(Map row, String key) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid booking field: $key');
    }
    return value;
  }

  static String _uid(Map row, String key) {
    final value = _text(row, key);
    if (!_uuid.hasMatch(value)) throw FormatException('Invalid booking $key');
    return value;
  }

  static String? _optionalUid(Map row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String || !_uuid.hasMatch(value)) {
      throw FormatException('Invalid booking $key');
    }
    return value;
  }

  static DateTime _date(Map row, String key) {
    final date = DateTime.tryParse(_text(row, key));
    if (date == null) throw FormatException('Invalid booking $key');
    return date;
  }

  static List<T> _rows<T>(Object? raw, T Function(Map<dynamic, dynamic>) parse) {
    if (raw is! List) throw const FormatException('Expected booking list');
    if (raw.length > 100) throw const FormatException('Booking list too large');
    return List<T>.unmodifiable(raw.map((item) {
      if (item is! Map) throw const FormatException('Malformed booking row');
      return parse(item);
    }));
  }

  static List<GarageBookingWorkshop> parseWorkshops(Object? raw) =>
      _rows(raw, (row) {
        final services = row['services'];
        if (services is! List || services.isEmpty ||
            services.length > 8 ||
            services.any((code) => code is! String ||
                !GarageBookingService.values.contains(code))) {
          throw const FormatException('Invalid workshop services');
        }
        return GarageBookingWorkshop(
          workspaceId: _uid(row, 'workspace_id'),
          name: _text(row, 'name'),
          city: _text(row, 'city'),
          country: _text(row, 'country'),
          timeZone: _text(row, 'time_zone'),
          services: List<String>.unmodifiable(services.cast<String>()),
        );
      });

  static List<GarageBookingSummary> parseMyRequests(Object? raw) =>
      _rows(raw, (row) {
        final service = _text(row, 'service');
        if (!GarageBookingService.values.contains(service)) {
          throw const FormatException('Invalid booking service');
        }
        return GarageBookingSummary(
          id: _uid(row, 'id'),
          workspaceId: _uid(row, 'workspace_id'),
          workshopName: _text(row, 'workshop_name'),
          startAt: _date(row, 'start_at'),
          status: _status(row['status']),
          service: service,
          workOrderId: _optionalUid(row, 'work_order_id'),
        );
      });

  static List<GarageBookingInboxItem> parseInbox(Object? raw) =>
      _rows(raw, (row) {
        final duration = row['duration_minutes'];
        final service = _text(row, 'service');
        if (duration is! int || !const {30, 60, 90, 120}.contains(duration) ||
            !GarageBookingService.values.contains(service)) {
          throw const FormatException('Invalid workshop booking duration/service');
        }
        final registration = row['registration'];
        if (registration != null && registration is! String) {
          throw const FormatException('Invalid booking registration');
        }
        return GarageBookingInboxItem(
          id: _uid(row, 'id'),
          customerName: _text(row, 'customer_name'),
          customerEmail: _text(row, 'customer_email'),
          vehicleMake: _text(row, 'vehicle_make'),
          vehicleModel: _text(row, 'vehicle_model'),
          registration: registration as String?,
          service: service,
          concern: _text(row, 'concern'),
          startAt: _date(row, 'start_at'),
          durationMinutes: duration,
          status: _status(row['status']),
        );
      });

  static String _uuidResult(Object? raw) {
    if (raw is! String || !_uuid.hasMatch(raw)) {
      throw const FormatException('Invalid booking ID returned by server');
    }
    return raw;
  }

  Future<List<GarageBookingWorkshop>> findWorkshops({String? city}) async {
    if (city != null && (city.trim().length < 2 || city.length > 80)) {
      throw ArgumentError.value(city, 'city');
    }
    final raw = await client.rpc(
      'garage_booking_discover',
      params: {'p_city': city?.trim()},
    );
    return parseWorkshops(raw);
  }

  static GarageBookingProfile? parseProfile(Object? raw, String workspaceId) {
    _id(workspaceId);
    if (raw is! List || raw.length > 1) throw const FormatException('Invalid profile rows');
    if (raw.isEmpty) return null;
    final row = raw.single;
    if (row is! Map) throw const FormatException('Invalid profile');
    final services = row['services'];
    final duration = row['duration_minutes'];
    if (_uid(row, 'workspace_id') != workspaceId ||
        services is! List || services.isEmpty || services.length > 8 ||
        services.toSet().length != services.length ||
        services.any((value) => value is! String || !GarageBookingService.values.contains(value)) ||
        duration is! int || !const {30, 60, 90, 120}.contains(duration) ||
        row['listed'] is! bool) throw const FormatException('Invalid profile fields');
    final city = _text(row, 'city');
    final zone = _text(row, 'time_zone');
    if (city.length < 2 || city.length > 80 || zone.length > 100) {
      throw const FormatException('Invalid profile location');
    }
    return GarageBookingProfile(workspaceId: workspaceId, city: city,
      timeZone: zone, services: List.unmodifiable(services.cast<String>()),
      durationMinutes: duration, listed: row['listed'] as bool);
  }

  Future<GarageBookingProfile?> profile(String workspaceId) async {
    final id = _id(workspaceId);
    final raw = await _privateRead(() => client.rpc(
      'garage_booking_profile', params: {'p_workspace': id}));
    return parseProfile(raw, id);
  }

  Future<bool> configure({
    required String workspaceId,
    required String city,
    required String timeZone,
    required List<String> services,
    required int durationMinutes,
    required bool listed,
  }) async {
    _requireSignIn();
    _id(workspaceId);
    if (city.trim().length < 2 || city.length > 80 ||
        timeZone.isEmpty || timeZone.length > 100 ||
        services.isEmpty || services.length > 8 ||
        services.any((code) => !GarageBookingService.values.contains(code)) ||
        !const {30,60,90,120}.contains(durationMinutes)) {
      throw ArgumentError('Invalid workshop booking configuration');
    }
    final raw = await client.rpc('garage_booking_configure', params: {
      'p_workspace': workspaceId,
      'p_city': city.trim(),
      'p_time_zone': timeZone,
      'p_services': services,
      'p_duration': durationMinutes,
      'p_listed': listed,
    });
    if (raw != true) throw const FormatException('Workshop opt-in not confirmed');
    return true;
  }

  /// No payment or guaranteed time is created here. Wait for workshop decision.
  Future<String> request({
    required String workspaceId,
    required String customerName,
    required String vehicleMake,
    required String vehicleModel,
    required String service,
    required String concern,
    required DateTime desiredStart,
    String? registration,
    String? requestKey,
  }) async {
    _requireSignIn();
    _id(workspaceId);
    if (requestKey != null) _id(requestKey);
    if (customerName.trim().length < 2 || customerName.length > 120 ||
        vehicleMake.trim().isEmpty || vehicleMake.length > 80 ||
        vehicleModel.trim().isEmpty || vehicleModel.length > 80 ||
        concern.trim().length < 3 || concern.length > 1000 ||
        (registration != null &&
          (registration.trim().isEmpty || registration.length > 30)) ||
        !GarageBookingService.values.contains(service) ||
        desiredStart.isBefore(DateTime.now().add(const Duration(hours:1))) ||
        desiredStart.isAfter(DateTime.now().add(const Duration(days:90)))) {
      throw ArgumentError('Invalid booking preference');
    }
    final raw = await client.rpc(requestKey == null
        ? 'garage_booking_request' : 'garage_booking_request_once', params: {
      if (requestKey != null) 'p_request_key': requestKey,
      'p_workspace': workspaceId,
      'p_name': customerName.trim(),
      'p_make': vehicleMake.trim(),
      'p_model': vehicleModel.trim(),
      'p_registration': registration?.trim(),
      'p_service': service,
      'p_concern': concern.trim(),
      'p_start_at': desiredStart.toUtc().toIso8601String(),
    });
    return _uuidResult(raw);
  }

  Future<List<GarageBookingSummary>> myRequests() async {
    final rows = await _privateRead(() => client.rpc('garage_booking_my_requests'));
    return parseMyRequests(rows);
  }

  Future<List<GarageBookingInboxItem>> workshopInbox(String workspaceId) async {
    final id = _id(workspaceId);
    final rows = await _privateRead(() => client.rpc(
      'garage_booking_shop_inbox', params: {'p_workspace': id}));
    return parseInbox(rows);
  }

  Future<GarageBookingStatus> respond(String bookingId, {required bool confirm}) async {
    _requireSignIn();
    final raw = await client.rpc('garage_booking_respond',
      params: {'p_booking': _id(bookingId), 'p_confirm': confirm});
    final parsed = _status(raw);
    if (parsed != (confirm ? GarageBookingStatus.confirmed : GarageBookingStatus.declined)) {
      throw const FormatException('Unexpected booking confirmation result');
    }
    return parsed;
  }

  Future<GarageBookingStatus> cancel(String bookingId) async {
    _requireSignIn();
    final raw = await client.rpc('garage_booking_cancel',
      params: {'p_booking': _id(bookingId)});
    final parsed = _status(raw);
    if (!const {GarageBookingStatus.withdrawn,
                 GarageBookingStatus.cancellationRequested,
                 GarageBookingStatus.cancelled}.contains(parsed)) {
      throw const FormatException('Unexpected cancellation result');
    }
    return parsed;
  }

  Future<void> confirmCancellation(String bookingId) async {
    _requireSignIn();
    final raw = await client.rpc('garage_booking_confirm_cancellation',
      params: {'p_booking': _id(bookingId)});
    if (raw != 'cancelled') {
      throw const FormatException('Workshop cancellation not confirmed');
    }
  }
}
