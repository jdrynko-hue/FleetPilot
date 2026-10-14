import 'package:supabase_flutter/supabase_flutter.dart';

import 'customer_quote_repository.dart';

/// Staging-only RepairBridge RPC adapter. Never reads tenant tables directly.
/// All authorization, exact-revision approval and revocation happen in SQL.
/// Keep this disconnected from public Fleet routes until Garage is deployed.
class RepairBridgeEvent {
  const RepairBridgeEvent(this.action, this.at, this.details);

  final String action;
  final DateTime at;
  final Map<String, dynamic> details;
}

class RepairBridgeSnapshot {
  RepairBridgeSnapshot({
    required this.requestId,
    required this.companyId,
    required this.workspaceId,
    required this.issueId,
    required this.issueTitle,
    required this.status,
    required this.workOrderId,
    required this.workOrderStatus,
    required this.sharedDescription,
    required this.sharedRegistration,
    required this.quote,
    required List<RepairBridgeEvent> events,
  }) : events = List.unmodifiable(events);

  final String requestId;
  final String companyId;
  final String workspaceId;
  final String issueId;
  final String issueTitle;
  final String status;
  final String? workOrderId;
  final String? workOrderStatus;
  final String? sharedDescription;
  final String? sharedRegistration;
  final GarageCustomerQuote? quote;
  final List<RepairBridgeEvent> events;
}

class RepairBridgeRepository {
  const RepairBridgeRepository(this.client);

  final SupabaseClient client;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const _statuses = {'received', 'diagnosing', 'awaiting_approval',
    'awaiting_parts', 'in_progress', 'ready', 'collected', 'cancelled'};
  static const _events = {'request_sent', 'request_accepted',
    'quote_approved', 'progress_updated', 'connection_revoked'};

  void _requireSignedIn() {
    if (client.auth.currentUser == null) {
      throw StateError('A signed-in Fleet or Garage account is required');
    }
  }

  static String requireUuid(String value, String label) {
    if (!_uuid.hasMatch(value)) {
      throw ArgumentError.value(value, label, 'UUID required');
    }
    return value;
  }

  Future<Object?> _rpc(String name, Map<String, Object?> params) async {
    _requireSignedIn();
    return client.rpc(name, params: params);
  }

  static String _uuidResult(Object? value) {
    if (value is! String || !_uuid.hasMatch(value)) {
      throw const FormatException('Server did not return a UUID');
    }
    return value;
  }

  Future<String> requestConnection(String companyId, String workspaceId) async =>
      _uuidResult(await _rpc('garage_fleet_request_connection', {
        'p_company': requireUuid(companyId, 'companyId'),
        'p_shop': requireUuid(workspaceId, 'workspaceId'),
      }));

  Future<String> acceptConnection(String companyId, String workspaceId) async =>
      _uuidResult(await _rpc('garage_fleet_accept_connection', {
        'p_company': requireUuid(companyId, 'companyId'),
        'p_shop': requireUuid(workspaceId, 'workspaceId'),
      }));

  /// The manager must opt into description and plate disclosure explicitly.
  /// No photos, driver profile or VIN are passed to this endpoint.
  Future<String> sendIssue({
    required String companyId,
    required String workspaceId,
    required String issueId,
    bool shareDescription = false,
    bool shareRegistration = false,
  }) async =>
      _uuidResult(await _rpc('garage_fleet_send_request', {
        'p_company': requireUuid(companyId, 'companyId'),
        'p_shop': requireUuid(workspaceId, 'workspaceId'),
        'p_issue': requireUuid(issueId, 'issueId'),
        'p_share_description': shareDescription,
        'p_share_registration': shareRegistration,
      }));

  Future<String> acceptRequest(String requestId) async =>
      _uuidResult(await _rpc('garage_fleet_accept_request', {
        'p_request': requireUuid(requestId, 'requestId'),
      }));

  /// The SQL transaction independently verifies the current quote revision.
  /// Do not optimistically display approval until this returns successfully.
  Future<int> approveQuote(String requestId, int revision) async {
    requireUuid(requestId, 'requestId');
    if (revision < 1 || revision > 100000) {
      throw RangeError.range(revision, 1, 100000, 'revision');
    }
    final result = await _rpc('garage_fleet_approve_quote', {
      'p_request': requestId, 'p_revision': revision,
    });
    if (result is! int || result != revision) {
      throw const FormatException('Quote approval revision mismatch');
    }
    return result;
  }

  Future<String> updateProgress(String requestId, String nextStatus) async {
    requireUuid(requestId, 'requestId');
    if (!const {'awaiting_parts', 'in_progress', 'ready', 'collected'}
        .contains(nextStatus)) {
      throw ArgumentError.value(nextStatus, 'nextStatus', 'Invalid transition');
    }
    final result = await _rpc('garage_fleet_update_progress', {
      'p_request': requestId, 'p_status': nextStatus,
    });
    if (result != nextStatus) {
      throw const FormatException('Server repair state mismatch');
    }
    return nextStatus;
  }

  Future<void> revokeConnection(String companyId, String workspaceId) async {
    final result = await _rpc('garage_fleet_revoke_connection', {
      'p_company': requireUuid(companyId, 'companyId'),
      'p_shop': requireUuid(workspaceId, 'workspaceId'),
    });
    if (result != true) {
      throw const FormatException('Revocation not confirmed');
    }
  }

  Future<RepairBridgeSnapshot> snapshot(String requestId) async {
    final payload = await _rpc('garage_fleet_snapshot', {
      'p_request': requireUuid(requestId, 'requestId'),
    });
    return parseSnapshot(payload);
  }

  /// Every refresh returns freshly parsed state; on authorization failure the
  /// caller must hide the previously rendered data rather than show stale PII.
  static RepairBridgeSnapshot parseSnapshot(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Invalid RepairBridge snapshot');
    }
    String requiredId(String key) {
      final value = raw[key];
      if (value is! String || !_uuid.hasMatch(value)) {
        throw FormatException('Invalid $key');
      }
      return value;
    }
    String? optionalText(String key) {
      final value = raw[key];
      if (value == null) return null;
      if (value is! String) throw FormatException('Invalid $key');
      return value;
    }
    final title = raw['issue_title'];
    if (title is! String || title.trim().isEmpty || title.length > 500) {
      throw const FormatException('Invalid issue title');
    }
    final status = raw['status'];
    if (status != 'sent' && status != 'accepted') {
      throw const FormatException('Invalid request state');
    }
    final orderId = optionalText('work_order_id');
    if (orderId != null && !_uuid.hasMatch(orderId)) {
      throw const FormatException('Invalid work-order reference');
    }
    final orderStatus = optionalText('work_order_status');
    if (orderStatus != null && !_statuses.contains(orderStatus)) {
      throw const FormatException('Invalid work-order state');
    }
    if ((status == 'sent' && orderId != null) ||
        (status == 'accepted' && orderId == null)) {
      throw const FormatException('Request/order state mismatch');
    }
    final quote = GarageCustomerQuoteRepository.parse(raw['quote']);
    if (quote != null && orderId == null) {
      throw const FormatException('Unlinked quote');
    }
    final eventRows = raw['events'];
    if (eventRows is! List) {
      throw const FormatException('Missing audit history');
    }
    final events = <RepairBridgeEvent>[];
    for (final entry in eventRows) {
      if (entry is! Map || !_events.contains(entry['action']) ||
          entry['details'] is! Map || entry['at'] is! String) {
        throw const FormatException('Malformed audit event');
      }
      final parsedAt = DateTime.tryParse(entry['at'] as String);
      if (parsedAt == null) throw const FormatException('Invalid audit time');
      events.add(RepairBridgeEvent(entry['action'] as String, parsedAt,
          Map<String, dynamic>.unmodifiable(
            (entry['details'] as Map).cast<String, dynamic>())));
    }
    if (events.isEmpty || events.first.action != 'request_sent') {
      throw const FormatException('Missing request creation audit');
    }
    return RepairBridgeSnapshot(
      requestId: requiredId('request_id'),
      companyId: requiredId('company_id'),
      workspaceId: requiredId('workspace_id'),
      issueId: requiredId('issue_id'),
      issueTitle: title,
      status: status as String,
      workOrderId: orderId,
      workOrderStatus: orderStatus,
      sharedDescription: optionalText('shared_description'),
      sharedRegistration: optionalText('shared_registration'),
      quote: quote,
      events: events,
    );
  }
}
