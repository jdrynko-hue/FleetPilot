import 'package:supabase_flutter/supabase_flutter.dart';

import 'customer_quote_repository.dart';

/// Scoped, authenticated RepairBridge RPC adapter.
///
/// Database RPCs enforce BOTH tenants' current membership and mutual consent.
/// Client checks are only defensive UX validation, never authorization.
/// Disabled from public Fleet navigation until Garage schema is safely released.
class GarageRepairBridgeRepository {
  const GarageRepairBridgeRepository(this.client);

  final SupabaseClient client;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  void _signedIn() {
    if (client.auth.currentUser == null) {
      throw StateError('A signed-in Fleet or Garage account is required');
    }
  }

  static void requireId(String value, String name) {
    if (!_uuid.hasMatch(value)) {
      throw ArgumentError.value(value, name, 'Valid UUID required');
    }
  }

  /// Server authorization remains authoritative; filter again for the open shop.
  Future<List<GarageRepairRequest>> requests(String workspaceId) async {
    _signedIn();
    requireId(workspaceId, 'workspaceId');
    final user = client.auth.currentUser!.id;
    final data = await client.rpc('garage_fleet_requests_for_me');
    if (client.auth.currentUser?.id != user) {
      throw StateError('Account changed');
    }
    return GarageRepairRequest.parseList(data, workspaceId);
  }

  Future<String> requestConnection(String companyId, String workspaceId) async {
    _signedIn();
    requireId(companyId, 'companyId');
    requireId(workspaceId, 'workspaceId');
    final result = await client.rpc('garage_fleet_request_connection',
        params: {'p_company': companyId, 'p_shop': workspaceId});
    return _rpcUuid(result);
  }

  Future<String> acceptConnection(String companyId, String workspaceId) async {
    _signedIn();
    requireId(companyId, 'companyId');
    requireId(workspaceId, 'workspaceId');
    final result = await client.rpc('garage_fleet_accept_connection',
        params: {'p_company': companyId, 'p_shop': workspaceId});
    return _rpcUuid(result);
  }

  /// Only an issue title crosses the boundary unless both optional
  /// disclosure flags are deliberately set to true.
  Future<String> sendIssue({
    required String companyId,
    required String workspaceId,
    required String issueId,
    bool shareDescription = false,
    bool shareRegistration = false,
  }) async {
    _signedIn();
    requireId(companyId, 'companyId');
    requireId(workspaceId, 'workspaceId');
    requireId(issueId, 'issueId');
    final result = await client.rpc('garage_fleet_send_request', params: {
      'p_company': companyId,
      'p_shop': workspaceId,
      'p_issue': issueId,
      'p_share_description': shareDescription,
      'p_share_registration': shareRegistration,
    });
    return _rpcUuid(result);
  }

  Future<String> acceptRepairRequest(String requestId) async {
    _signedIn();
    requireId(requestId, 'requestId');
    final result = await client.rpc('garage_fleet_accept_request',
        params: {'p_request': requestId});
    return _rpcUuid(result);
  }

  Future<GarageRepairBridgeSnapshot> load(String requestId) async {
    _signedIn();
    requireId(requestId, 'requestId');
    final user = client.auth.currentUser!.id;
    final result = await client.rpc('garage_fleet_snapshot',
        params: {'p_request': requestId});
    if (client.auth.currentUser?.id != user) throw StateError('Account changed');
    final snapshot = GarageRepairBridgeSnapshot.parse(result);
    if (snapshot.requestId != requestId) {
      throw const FormatException('Unexpected RepairBridge request');
    }
    return snapshot;
  }

  Future<int> approveQuote(String requestId, int exactRevision) async {
    _signedIn();
    requireId(requestId, 'requestId');
    if (exactRevision < 1) throw RangeError.value(exactRevision, 'exactRevision');
    final result = await client.rpc('garage_fleet_approve_quote', params: {
      'p_request': requestId,
      'p_revision': exactRevision,
    });
    if (result is! int || result != exactRevision) {
      throw const FormatException('Unexpected quote approval revision');
    }
    return result;
  }

  Future<String> updateProgress(String requestId, String nextStatus) async {
    _signedIn();
    requireId(requestId, 'requestId');
    if (!const {'awaiting_parts', 'in_progress', 'ready', 'collected'}
        .contains(nextStatus)) {
      throw ArgumentError.value(nextStatus, 'nextStatus', 'Invalid transition');
    }
    final result = await client.rpc('garage_fleet_update_progress', params: {
      'p_request': requestId,
      'p_status': nextStatus,
    });
    if (result != nextStatus) {
      throw const FormatException('Unexpected repair progress confirmation');
    }
    return nextStatus;
  }

  Future<bool> revokeConnection(String companyId, String workspaceId) async {
    _signedIn();
    requireId(companyId, 'companyId');
    requireId(workspaceId, 'workspaceId');
    final result = await client.rpc('garage_fleet_revoke_connection',
        params: {'p_company': companyId, 'p_shop': workspaceId});
    if (result is! bool || !result) {
      throw const FormatException('Connection revocation not confirmed');
    }
    return true;
  }

  static String _rpcUuid(Object? value) {
    if (value is! String || !_uuid.hasMatch(value)) {
      throw const FormatException('Server returned an invalid UUID');
    }
    return value;
  }
}

class GarageRepairBridgeEvent {
  GarageRepairBridgeEvent(this.action, this.occurredAt, Map<String, Object?> details)
      : details = Map.unmodifiable(details);

  final String action;
  final DateTime occurredAt;
  /// Only allowed audit keys are copied; unknown data is never displayed.
  final Map<String, Object?> details;
}

class GarageRepairBridgeSnapshot {
  GarageRepairBridgeSnapshot({
    required this.requestId,
    required this.companyId,
    required this.workspaceId,
    required this.issueId,
    required this.title,
    required this.status,
    required this.workOrderId,
    required this.workOrderStatus,
    required this.sharedDescription,
    required this.sharedRegistration,
    required this.quote,
    required List<GarageRepairBridgeEvent> events,
  }) : events = List.unmodifiable(events);

  final String requestId;
  final String companyId;
  final String workspaceId;
  final String issueId;
  final String title;
  final String status;
  final String? workOrderId;
  final String? workOrderStatus;
  final String? sharedDescription;
  final String? sharedRegistration;
  final GarageCustomerQuote? quote;
  final List<GarageRepairBridgeEvent> events;

  bool get needsFleetApproval =>
      status == 'accepted' &&
      workOrderStatus == 'awaiting_approval' &&
      quote != null && !quote!.approved;

  static GarageRepairBridgeSnapshot parse(Object? payload) {
    if (payload is! Map) {
      throw const FormatException('Invalid RepairBridge response');
    }
    final id = _uuidField(payload, 'request_id');
    final company = _uuidField(payload, 'company_id');
    final workspace = _uuidField(payload, 'workspace_id');
    final issue = _uuidField(payload, 'issue_id');
    final title = _requiredText(payload, 'issue_title');
    final status = _requiredText(payload, 'status');
    if (!const {'sent', 'accepted'}.contains(status)) {
      throw const FormatException('Unknown RepairBridge request status');
    }
    final orderId = _optionalUuid(payload, 'work_order_id');
    final orderStatus = _optionalText(payload, 'work_order_status');
    if (orderStatus != null && !const {
      'received', 'diagnosing', 'awaiting_approval', 'awaiting_parts',
      'in_progress', 'ready', 'collected', 'cancelled',
    }.contains(orderStatus)) {
      throw const FormatException('Unknown workshop repair status');
    }
    if ((status == 'accepted') != (orderId != null) ||
        (orderId == null && orderStatus != null) ||
        (orderId != null && orderStatus == null)) {
      throw const FormatException('Inconsistent RepairBridge work order');
    }
    final desc = _optionalText(payload, 'shared_description');
    final reg = _optionalText(payload, 'shared_registration');
    final rawQuote = payload['quote'];
    final quote = GarageCustomerQuoteRepository.parse(rawQuote);
    if (quote != null && (status != 'accepted' || orderId == null)) {
      throw const FormatException('Quote exists without an accepted repair');
    }
    final rawEvents = payload['events'];
    if (rawEvents is! List || rawEvents.isEmpty || rawEvents.length > 10000) {
      throw const FormatException('Invalid RepairBridge event history');
    }
    final events = <GarageRepairBridgeEvent>[];
    DateTime? previous;
    for (final item in rawEvents) {
      if (item is! Map) throw const FormatException('Invalid repair event');
      final action = _requiredText(item, 'action');
      if (!const {
        'request_sent','request_accepted','quote_approved',
        'progress_updated','connection_revoked',
      }.contains(action)) {
        throw const FormatException('Unknown repair event action');
      }
      final instant = DateTime.tryParse(_requiredText(item, 'at'));
      if (instant == null) {
        throw const FormatException('Invalid repair event time');
      }
      if (previous != null && instant.isBefore(previous)) {
        throw const FormatException('Unordered repair history');
      }
      final rawDetails = item['details'];
      if (rawDetails is! Map) {
        throw const FormatException('Invalid repair event details');
      }
      final details = <String, Object?>{};
      if (action == 'quote_approved') {
        final revision = rawDetails['revision'];
        if (revision is! int || revision < 1) {
          throw const FormatException('Invalid approved quote revision event');
        }
        details['revision'] = revision;
      }
      if (action == 'progress_updated') {
        final from = rawDetails['from'];
        final to = rawDetails['to'];
        if (from is! String || to is! String ||
            !const {
              'received','diagnosing','awaiting_approval','awaiting_parts',
              'in_progress','ready','collected','cancelled'
            }.contains(from) ||
            !const {
              'received','diagnosing','awaiting_approval','awaiting_parts',
              'in_progress','ready','collected','cancelled'
            }.contains(to)) {
          throw const FormatException('Invalid repair progress event');
        }
        details['from'] = from;
        details['to'] = to;
      }
      previous = instant;
      events.add(GarageRepairBridgeEvent(action, instant, details));
    }
    if (events.first.action != 'request_sent') {
      throw const FormatException('Missing RepairBridge request event');
    }
    return GarageRepairBridgeSnapshot(
      requestId: id,
      companyId: company,
      workspaceId: workspace,
      issueId: issue,
      title: title,
      status: status,
      workOrderId: orderId,
      workOrderStatus: orderStatus,
      sharedDescription: desc,
      sharedRegistration: reg,
      quote: quote,
      events: events,
    );
  }

  static String _uuidField(Map<dynamic,dynamic> data,String key) {
    final value = _requiredText(data,key);
    if (!GarageRepairBridgeRepository._uuid.hasMatch(value)) {
      throw FormatException('Invalid $key');
    }
    return value;
  }
  static String? _optionalUuid(Map<dynamic,dynamic> data,String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('Invalid $key');
    if (!GarageRepairBridgeRepository._uuid.hasMatch(value)) {
      throw FormatException('Invalid $key');
    }
    return value;
  }
  static String _requiredText(Map<dynamic,dynamic> data,String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid $key');
    }
    return value;
  }
  static String? _optionalText(Map<dynamic,dynamic> data,String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid $key');
    }
    return value;
  }
}

/// The inbox intentionally contains no private Fleet description or registration.
class GarageRepairRequest {
  const GarageRepairRequest(this.id, this.companyId, this.workspaceId,
      this.title, this.status);
  final String id;
  final String companyId;
  final String workspaceId;
  final String title;
  final String status;

  static List<GarageRepairRequest> parseList(Object? data, String workspaceId) {
    GarageRepairBridgeRepository.requireId(workspaceId, 'workspaceId');
    if (data is! List) throw const FormatException('Invalid repair inbox');
    final rows = <GarageRepairRequest>[];
    final ids = <String>{};
    for (final row in data) {
      if (row is! Map) throw const FormatException('Invalid repair request');
      final id = GarageRepairBridgeSnapshot._uuidField(row, 'request_id');
      final company = GarageRepairBridgeSnapshot._uuidField(row, 'company_id');
      final shop = GarageRepairBridgeSnapshot._uuidField(row, 'workspace_id');
      final title = GarageRepairBridgeSnapshot._requiredText(row, 'issue_title');
      final status = row['request_status'];
      if (!const {'sent', 'accepted'}.contains(status) || !ids.add(id)) {
        throw const FormatException('Invalid repair request status or duplicate');
      }
      if (shop == workspaceId) {
        rows.add(GarageRepairRequest(id, company, shop, title, status as String));
      }
    }
    rows.sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(rows);
  }
}
