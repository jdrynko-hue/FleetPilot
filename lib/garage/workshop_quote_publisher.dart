import 'package:supabase_flutter/supabase_flutter.dart';

import 'garage_currencies.dart';

/// Separate owner/adviser quote publishing API. The server independently
/// checks garage membership, quote status and the revision currency.
/// This adapter is not yet mounted in the public Fleet application.
class GarageWorkshopQuotePublisher {
  const GarageWorkshopQuotePublisher(this.client);

  final SupabaseClient client;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static Map<String, Object> payload({
    required String currency,
    required List<GarageQuoteDraftLine> lines,
  }) {
    GarageCurrencies.digits(currency); // Refuse unrecognized ISO codes.
    if (lines.isEmpty || lines.length > 50) {
      throw ArgumentError('Quote must have between 1 and 50 lines');
    }
    return {
      'p_currency': currency,
      'p_lines': List<Map<String, Object>>.unmodifiable(
        lines.map((line) => line.toJson()),
      ),
    };
  }

  Future<int> publish({
    required String workspaceId,
    required String orderId,
    required String currency,
    required List<GarageQuoteDraftLine> lines,
  }) async {
    if (!_uuid.hasMatch(workspaceId) || !_uuid.hasMatch(orderId)) {
      throw ArgumentError('Valid workspace and order IDs required');
    }
    if (client.auth.currentUser == null) {
      throw StateError('Workshop owner or adviser must be signed in');
    }
    final body = payload(currency: currency, lines: lines);
    final result = await client.rpc(
      'garage_publish_quote',
      params: {
        'p_workspace_id': workspaceId,
        'p_order_id': orderId,
        ...body,
      },
    );
    if (result is! int || result < 1) {
      throw const FormatException('Invalid revision returned by server');
    }
    return result;
  }
}

class GarageQuoteDraftLine {
  const GarageQuoteDraftLine({
    required this.type,
    required this.description,
    required this.quantity,
    required this.unitPriceMinor,
    required this.taxMinor,
  });

  final String type;
  final String description;
  final int quantity;
  final int unitPriceMinor;
  final int taxMinor;

  Map<String, Object> toJson() {
    if (!const {'labour', 'part', 'other'}.contains(type) ||
        description.trim().length < 2 || description.length > 500 ||
        quantity < 1 || quantity > 1000 ||
        unitPriceMinor < 0 || unitPriceMinor > 1000000000 ||
        taxMinor < 0 || taxMinor > 1000000000) {
      throw ArgumentError('Invalid line values');
    }
    return {
      'type': type,
      'description': description.trim(),
      'quantity': quantity,
      'unit_price_minor': unitPriceMinor,
      'tax_minor': taxMinor,
    };
  }
}
