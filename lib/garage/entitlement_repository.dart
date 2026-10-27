import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';

enum GarageEntitlementSource { trial, paid }

enum GaragePaymentState { failed, paid }

class GarageEntitlement {
  const GarageEntitlement({required this.active, this.source,
    this.accessEndsAt, this.lastPaymentState});

  final bool active;
  final GarageEntitlementSource? source;
  final DateTime? accessEndsAt;
  final GaragePaymentState? lastPaymentState;

  static GarageEntitlement parse(Object? value) {
    if (value is! Map) throw const FormatException('Invalid entitlement');
    const expected = {'active', 'source', 'access_ends_at', 'last_payment_state'};
    if (value.keys.any((key) => key is! String) ||
        value.keys.cast<String>().toSet().difference(expected).isNotEmpty ||
        expected.difference(value.keys.cast<String>().toSet()).isNotEmpty ||
        value['active'] is! bool) {
      throw const FormatException('Invalid entitlement');
    }
    final source = switch (value['source']) {
      null => null,
      'trial' => GarageEntitlementSource.trial,
      'paid' => GarageEntitlementSource.paid,
      _ => throw const FormatException('Invalid entitlement'),
    };
    final payment = switch (value['last_payment_state']) {
      null => null,
      'failed' => GaragePaymentState.failed,
      'paid' => GaragePaymentState.paid,
      _ => throw const FormatException('Invalid entitlement'),
    };
    DateTime? accessEndsAt;
    if (value['access_ends_at'] != null) {
      if (value['access_ends_at'] is! String) {
        throw const FormatException('Invalid entitlement');
      }
      accessEndsAt = DateTime.tryParse(value['access_ends_at'] as String)?.toUtc();
      if (accessEndsAt == null) {
        throw const FormatException('Invalid entitlement');
      }
    }
    final active = value['active'] as bool;
    if (active != (source != null && accessEndsAt != null)) {
      throw const FormatException('Invalid entitlement');
    }
    return GarageEntitlement(active: active, source: source,
      accessEndsAt: accessEndsAt, lastPaymentState: payment);
  }
}

enum GarageEntitlementReadState { disabled, verified, unavailable }

class GarageEntitlementRead {
  const GarageEntitlementRead._(this._state, this._entitlement,
      [this._trialAvailable = false, this._contextCurrent]);
  const GarageEntitlementRead.disabled()
      : this._(GarageEntitlementReadState.disabled, null);
  const GarageEntitlementRead.unavailable()
      : this._(GarageEntitlementReadState.unavailable, null);
  const GarageEntitlementRead.verified(GarageEntitlement value,
      {bool trialAvailable = false, bool Function()? contextCurrent})
      : this._(GarageEntitlementReadState.verified, value, trialAvailable, contextCurrent);

  final bool _trialAvailable;
  final GarageEntitlementReadState _state;
  final GarageEntitlement? _entitlement;
  final bool Function()? _contextCurrent;
  bool get isCurrent => _contextCurrent?.call() ?? true;
  bool get trialAvailable => isCurrent && _trialAvailable;
  GarageEntitlementReadState get state => isCurrent
      ? _state : GarageEntitlementReadState.unavailable;
  GarageEntitlement? get entitlement => isCurrent ? _entitlement : null;
  // An authoritative grant is valid only inside the server-confirmed period.
  // A cached positive response must not keep access open after expiry.
  bool allowsPaidFeaturesAt(DateTime instant) {
    final accessEnd = entitlement?.accessEndsAt;
    return state == GarageEntitlementReadState.verified &&
        entitlement?.active == true &&
        accessEnd != null && accessEnd.isAfter(instant.toUtc());
  }

  bool get allowsPaidFeatures => allowsPaidFeaturesAt(DateTime.now().toUtc());
}

typedef GarageEntitlementInvoke = Future<Object?> Function(String workspaceId);

/// Reads the member-scoped server decision. It never reads Stripe state and
/// treats configuration, transport, account-change and response errors alike:
/// paid features are not allowed.
class GarageEntitlementRepository {
  const GarageEntitlementRepository({required this.enabled,
    required this.supabaseUrl, required this.currentUserId,
    this.currentSessionKey, required this.invoke, this.billingStatus = false});

  factory GarageEntitlementRepository.forClient(SupabaseClient client, {bool billingStatus = false}) =>
      GarageEntitlementRepository(
        enabled: AppConfig.garageSandboxEntitlementEnabled,
        billingStatus: billingStatus,
        supabaseUrl: AppConfig.supabaseUrl,
        currentUserId: () => client.auth.currentUser?.id,
        currentSessionKey: () => client.auth.currentSession?.accessToken,
        invoke: (workspaceId) async => (await client.functions.invoke(
          'flotaryx-garage-test-entitlement',
          body: {'workspace_id': workspaceId, if (billingStatus) 'billing_status': true},
        )).data,
      );

  final bool billingStatus;
  final bool enabled;
  final String supabaseUrl;
  final String? Function() currentUserId;
  // Compare the SDK access token in memory only; never send or log it.
  // Same user ID does not imply the same authenticated session.
  final String? Function()? currentSessionKey;
  final GarageEntitlementInvoke invoke;

  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');

  Future<GarageEntitlementRead> load(String workspaceId) async {
    if (!enabled) return const GarageEntitlementRead.disabled();
    if (!AppConfig.isEcosystemQaBackend(supabaseUrl) ||
        !_uuid.hasMatch(workspaceId)) {
      return const GarageEntitlementRead.unavailable();
    }
    final actor = currentUserId();
    if (actor == null || !_uuid.hasMatch(actor)) {
      return const GarageEntitlementRead.unavailable();
    }
    // A disabled or replaced SDK session must never inherit an older grant.
    final sessionKey = currentSessionKey?.call();
    if (currentSessionKey != null && (sessionKey == null || sessionKey.isEmpty)) {
      return const GarageEntitlementRead.unavailable();
    }
    try {
      final raw = await invoke(workspaceId).timeout(const Duration(seconds: 12));
      if (currentUserId() != actor ||
          (currentSessionKey != null && currentSessionKey!() != sessionKey)) {
        return const GarageEntitlementRead.unavailable();
      }
      // Keep the completed result tied to the same in-memory Auth context.
      // Once an observed mismatch invalidates it, returning to an old identity
      // cannot revive the cached result; obtain a new server decision instead.
      var invalidated = false;
      bool contextCurrent() {
        invalidated = invalidated || currentUserId() != actor ||
          (currentSessionKey != null && currentSessionKey!() != sessionKey);
        return !invalidated;
      }
      if (billingStatus) {
        if (raw is! Map || raw.length != 2 || !raw.containsKey('entitlement') ||
            raw['trial_available'] is! bool) throw const FormatException('Invalid billing status');
        final status = GarageEntitlement.parse(raw['entitlement']);
        if (status.active && raw['trial_available'] == true) {
          throw const FormatException('Invalid billing status');
        }
        return GarageEntitlementRead.verified(status,
          trialAvailable: raw['trial_available'] as bool, contextCurrent: contextCurrent);
      }
      return GarageEntitlementRead.verified(GarageEntitlement.parse(raw), contextCurrent: contextCurrent);
    } catch (_) {
      return const GarageEntitlementRead.unavailable();
    }
  }
}
