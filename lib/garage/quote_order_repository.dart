import 'package:supabase_flutter/supabase_flutter.dart';

import 'garage_currencies.dart';

/// Read-only, tenant-scoped staff projections for the QA quote editor.
///
/// Navigation and client-side validation are not security boundaries. RLS
/// independently requires owner/service_adviser access to quote revisions;
/// the publisher RPC enforces both authorization and work-order state.
class GarageQuoteOrder {
  const GarageQuoteOrder({
    required this.id, required this.complaint, required this.status,
  });

  final String id;
  final String complaint;
  final String status;

  bool get canQuote => status == 'diagnosing' || status == 'awaiting_approval';
}

class GarageQuoteCurrencySelection {
  const GarageQuoteCurrencySelection(this.code, {required this.locked});
  final String code;
  final bool locked;
}

class GarageQuoteOrderRepository {
  const GarageQuoteOrderRepository(this.client);

  final SupabaseClient client;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const _statuses = {
    'received', 'diagnosing', 'awaiting_approval', 'awaiting_parts',
    'in_progress', 'ready', 'collected', 'cancelled',
  };

  static String validateId(String id) {
    if (!_uuid.hasMatch(id)) throw ArgumentError.value(id, 'id', 'Invalid UUID');
    return id;
  }

  void _requireAuth() {
    if (client.auth.currentUser == null) throw StateError('Sign in required');
  }

  static List<GarageQuoteOrder> parseOrders(Object? data) {
    if (data is! List || data.length > 100) {
      throw const FormatException('Invalid order listing');
    }
    return List.unmodifiable(data.map((item) {
      if (item is! Map || item['id'] is! String ||
          !_uuid.hasMatch(item['id'] as String) ||
          item['complaint'] is! String ||
          (item['complaint'] as String).trim().isEmpty ||
          (item['complaint'] as String).length > 4000 ||
          !_statuses.contains(item['status'])) {
        throw const FormatException('Invalid work order');
      }
      return GarageQuoteOrder(
        id: item['id'] as String,
        complaint: item['complaint'] as String,
        status: item['status'] as String,
      );
    }));
  }

  Future<List<GarageQuoteOrder>> orders(String workspaceId) async {
    _requireAuth();
    validateId(workspaceId);
    final rows = await client.from('garage_work_orders')
        .select('id,complaint,status')
        .eq('workspace_id', workspaceId)
        .order('received_at', ascending: false).limit(100);
    return parseOrders(rows);
  }

  /// An existing quote series fixes the currency for all later revisions.
  /// Never fall back to a default if the current series cannot be verified.
  Future<GarageQuoteCurrencySelection> currency(
      String workspaceId, String orderId) async {
    _requireAuth();
    validateId(workspaceId);
    validateId(orderId);
    final revisions = await client.from('garage_quote_revisions')
        .select('currency')
        .eq('workspace_id', workspaceId).eq('order_id', orderId)
        .order('revision', ascending: false).limit(1);
    if (revisions.isNotEmpty) {
      final code = revisions.first['currency'];
      if (code is! String) throw const FormatException('Invalid quote currency');
      GarageCurrencies.digits(code);
      return GarageQuoteCurrencySelection(code, locked: true);
    }
    final workshop = await client.from('garage_workspaces')
        .select('currency').eq('id', workspaceId).single();
    final code = workshop['currency'];
    if (code is! String) throw const FormatException('Invalid workshop currency');
    GarageCurrencies.digits(code);
    return GarageQuoteCurrencySelection(code, locked: false);
  }
}

/// Parse displayed money exactly using integer minor units, never doubles.
int parseGarageMajorAmount(String currency, String input) {
  final digits = GarageCurrencies.digits(currency);
  final match = RegExp(r'^([0-9]{1,9})(?:[.,]([0-9]{1,3}))?$')
      .firstMatch(input.trim());
  if (match == null) throw const FormatException('Invalid amount');
  final fraction = match.group(2) ?? '';
  if ((digits == 0 && fraction.isNotEmpty) || fraction.length > digits) {
    throw const FormatException('Too many decimal places');
  }
  var factor = 1;
  for (var i = 0; i < digits; i++) { factor *= 10; }
  final minor = int.parse(match.group(1)!) * factor +
      (fraction.isEmpty ? 0 : int.parse(fraction.padRight(digits, '0')));
  if (minor > 1000000000) throw const FormatException('Amount too large');
  return minor;
}
