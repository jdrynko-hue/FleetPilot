import 'package:supabase_flutter/supabase_flutter.dart';

import 'garage_currencies.dart';

/// Minimal, independently authorized private-customer quote projection.
///
/// The server checks the signed-in user's verified email against the
/// individual vehicle customer; the client never supplies an approver ID.
/// No corporate/Fleet approval is supported by this adapter.
class GarageCustomerQuoteLine {
  const GarageCustomerQuoteLine({
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

  int get subtotalMinor => quantity * unitPriceMinor;
  int get totalMinor => subtotalMinor + taxMinor;
}

class GarageCustomerQuote {
  GarageCustomerQuote({
    required this.revision,
    required this.currency,
    required this.subtotalMinor,
    required this.taxMinor,
    required this.totalMinor,
    required this.approved,
    required List<GarageCustomerQuoteLine> lines,
  }) : lines = List.unmodifiable(lines);

  final int revision;
  final String currency;
  final int subtotalMinor;
  final int taxMinor;
  final int totalMinor;
  final bool approved;
  final List<GarageCustomerQuoteLine> lines;

  /// Every amount is an integer of the selected ISO currency's minor unit.
  /// Sterling/cents/grosz are 2 digits; JPY is 0, KWD is 3.
  static final supportedCurrencies =
      Set<String>.unmodifiable(GarageCurrencies.fractionDigits.keys);

  String formatMinor(int minor) =>
      GarageCurrencies.formatMinor(currency, minor);
}

class GarageCustomerQuoteRepository {
  const GarageCustomerQuoteRepository(this.client);

  final SupabaseClient client;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  void _requireIdentity(String workspaceId, String orderId) {
    if (!_uuid.hasMatch(workspaceId) || !_uuid.hasMatch(orderId)) {
      throw ArgumentError('Valid Garage workspace and work-order IDs required');
    }
    if (client.auth.currentUser == null) {
      throw StateError('A verified customer account must be signed in');
    }
  }

  Future<GarageCustomerQuote?> load(
    String workspaceId,
    String orderId,
  ) async {
    _requireIdentity(workspaceId, orderId);
    final response = await client.rpc(
      'garage_customer_current_quote',
      params: {
        'p_workspace_id': workspaceId,
        'p_order_id': orderId,
      },
    );
    return parse(response);
  }

  /// Server locks the order, independently checks actual Auth identity and
  /// refuses stale, repeated or business-customer approvals.
  Future<int> approve(
    String workspaceId,
    String orderId,
    int revision,
  ) async {
    _requireIdentity(workspaceId, orderId);
    if (revision < 1) {
      throw RangeError.value(revision, 'revision');
    }
    final response = await client.rpc(
      'garage_customer_approve_quote',
      params: {
        'p_workspace_id': workspaceId,
        'p_order_id': orderId,
        'p_revision': revision,
      },
    );
    if (response is! int || response != revision) {
      throw const FormatException('Quote approval revision mismatch');
    }
    return response;
  }

  static GarageCustomerQuote? parse(Object? payload) {
    if (payload == null) return null;
    if (payload is! Map) {
      throw const FormatException('Invalid customer quote response');
    }
    final revision = _positiveInt(payload, 'revision');
    final currency = _text(payload, 'currency');
    if (!GarageCustomerQuote.supportedCurrencies.contains(currency)) {
      throw const FormatException('Unsupported quote currency');
    }
    final subtotal = _nonNegativeInt(payload, 'subtotal_minor');
    final tax = _nonNegativeInt(payload, 'tax_minor');
    final total = _nonNegativeInt(payload, 'total_minor');
    final approved = payload['approved'];
    if (approved is! bool) {
      throw const FormatException('Invalid approval state');
    }
    final rawLines = payload['lines'];
    if (rawLines is! List || rawLines.isEmpty || rawLines.length > 50) {
      throw const FormatException('Invalid quote line count');
    }

    var summedSubtotal = 0;
    var summedTax = 0;
    final lines = <GarageCustomerQuoteLine>[];
    for (final raw in rawLines) {
      if (raw is! Map) {
        throw const FormatException('Invalid quote line');
      }
      final type = _text(raw, 'type');
      if (!const {'labour', 'part', 'other'}.contains(type)) {
        throw const FormatException('Unsupported quote line type');
      }
      final description = _text(raw, 'description');
      final quantity = _positiveInt(raw, 'quantity');
      final unit = _nonNegativeInt(raw, 'unit_price_minor');
      final lineTax = _nonNegativeInt(raw, 'tax_minor');
      if (quantity > 1000 || description.length > 500 ||
          unit > 1000000000 || lineTax > 1000000000) {
        throw const FormatException('Quote value exceeds safe limits');
      }
      final line = GarageCustomerQuoteLine(
        type: type,
        description: description,
        quantity: quantity,
        unitPriceMinor: unit,
        taxMinor: lineTax,
      );
      lines.add(line);
      summedSubtotal += line.subtotalMinor;
      summedTax += line.taxMinor;
    }
    if (subtotal != summedSubtotal ||
        tax != summedTax ||
        total != subtotal + tax) {
      throw const FormatException('Quote line totals do not match');
    }
    return GarageCustomerQuote(
      revision: revision,
      currency: currency,
      subtotalMinor: subtotal,
      taxMinor: tax,
      totalMinor: total,
      approved: approved,
      lines: lines,
    );
  }

  static String _text(Map<dynamic, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid quote field: $key');
    }
    return value;
  }

  static int _positiveInt(Map<dynamic, dynamic> data, String key) {
    final value = _nonNegativeInt(data, key);
    if (value == 0) throw FormatException('Expected positive $key');
    return value;
  }

  static int _nonNegativeInt(Map<dynamic, dynamic> data, String key) {
    final value = data[key];
    if (value is! int || value < 0) {
      throw FormatException('Invalid nonnegative quote amount: $key');
    }
    return value;
  }
}
