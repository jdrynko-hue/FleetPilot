import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'garage_currencies.dart';
import 'garage_ui_text.dart';
import 'quote_currency_picker.dart';
import 'quote_order_repository.dart';
import 'workshop_quote_publisher.dart';

/// Staff-only QA order inbox. Backend RLS is authoritative for every row.
class GarageWorkshopQuotesScreen extends StatefulWidget {
  const GarageWorkshopQuotesScreen({
    required this.loadOrders, required this.loadCurrency,
    required this.publish, super.key,
  });

  factory GarageWorkshopQuotesScreen.forClient({
    required SupabaseClient client, required String workspaceId, Key? key,
  }) {
    final orders = GarageQuoteOrderRepository(client);
    final publisher = GarageWorkshopQuotePublisher(client);
    return GarageWorkshopQuotesScreen(
      key: key,
      loadOrders: () => orders.orders(workspaceId),
      loadCurrency: (id) => orders.currency(workspaceId, id),
      publish: (id, currency, lines) => publisher.publish(
        workspaceId: workspaceId, orderId: id, currency: currency,
        lines: lines,
      ),
    );
  }

  final Future<List<GarageQuoteOrder>> Function() loadOrders;
  final Future<GarageQuoteCurrencySelection> Function(String) loadCurrency;
  final Future<int> Function(String, String, List<GarageQuoteDraftLine>) publish;

  @override
  State<GarageWorkshopQuotesScreen> createState() => _WorkshopQuotesState();
}

class _WorkshopQuotesState extends State<GarageWorkshopQuotesScreen> {
  List<GarageQuoteOrder> _orders = const [];
  bool _loading = true;
  String? _error;
  int _version = 0;

  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void dispose() { _version++; super.dispose(); }

  Future<void> _refresh() async {
    final current = ++_version;
    setState(() { _orders = const []; _loading = true; _error = null; });
    try {
      final rows = await widget.loadOrders();
      if (mounted && _version == current) {
        setState(() => _orders = List.unmodifiable(rows));
      }
    } catch (_) {
      if (mounted && _version == current) {
        setState(() => _error = GarageUiText.get('quoteLoadError'));
      }
    } finally {
      if (mounted && _version == current) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(GarageQuoteOrder order) async {
    if (_loading || !order.canQuote) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => GarageQuoteEditorScreen(
        order: order,
        loadCurrency: () => widget.loadCurrency(order.id),
        publish: (currency, lines) => widget.publish(order.id, currency, lines),
      ),
    ));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(GarageUiText.get('workshopEstimates')),
      actions: [IconButton(key: const Key('quote_orders_refresh'),
        icon: const Icon(Icons.refresh), onPressed: _loading ? null : _refresh)]),
    body: SafeArea(child: _loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(16), children: [
        Text(GarageUiText.get('quoteIntro')),
        if (_error != null) Text(_error!, key: const Key('quote_orders_error')),
        if (_orders.isEmpty) Text(GarageUiText.get('quoteNoOrders'),
          key: const Key('quote_orders_empty')),
        for (final order in _orders) Card(
          child: ListTile(
            key: Key('quote_order_${order.id}'),
            title: Text(order.complaint, maxLines: 3,
              overflow: TextOverflow.ellipsis),
            subtitle: Text(order.status.replaceAll('_',' ')),
            trailing: order.canQuote
              ? const Icon(Icons.chevron_right) : const Icon(Icons.lock_outline),
            onTap: order.canQuote ? () => _open(order) : null,
          ),
        ),
      ])),
  );
}

class _QuoteDraft {
  final description = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unitPrice = TextEditingController();
  final tax = TextEditingController(text: '0');
  String type = 'labour';

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitPrice.dispose();
    tax.dispose();
  }

  GarageQuoteDraftLine toLine(String currency) {
    final qty = int.tryParse(quantity.text.trim());
    if (qty == null || qty < 1 || qty > 1000) {
      throw const FormatException('Quantity must be between 1 and 1000');
    }
    final line = GarageQuoteDraftLine(
      type: type, description: description.text,
      quantity: qty,
      unitPriceMinor: parseGarageMajorAmount(currency, unitPrice.text),
      taxMinor: parseGarageMajorAmount(currency, tax.text),
    );
    line.toJson(); // Enforce exactly the publisher's validation.
    return line;
  }
}

/// QA-only authenticated quote editor. Approval is deliberately not performed
/// by workshop staff and remains in a separate customer/Fleet route.
class GarageQuoteEditorScreen extends StatefulWidget {
  const GarageQuoteEditorScreen({
    required this.order, required this.loadCurrency,
    required this.publish, super.key,
  });

  final GarageQuoteOrder order;
  final Future<GarageQuoteCurrencySelection> Function() loadCurrency;
  final Future<int> Function(String, List<GarageQuoteDraftLine>) publish;

  @override
  State<GarageQuoteEditorScreen> createState() => _QuoteEditorState();
}

class _QuoteEditorState extends State<GarageQuoteEditorScreen> {
  final List<_QuoteDraft> _lines = [_QuoteDraft()];
  GarageQuoteCurrencySelection? _currency;
  String? _error;
  bool _loading = true;
  bool _publishing = false;
  bool _uncertain = false;
  int? _published;

  @override
  void initState() { super.initState(); _loadCurrency(); }
  @override
  void dispose() {
    for (final line in _lines) { line.dispose(); }
    super.dispose();
  }

  Future<void> _loadCurrency() async {
    setState(() { _loading = true; _currency = null; _error = null; });
    try {
      final currency = await widget.loadCurrency();
      GarageCurrencies.digits(currency.code);
      if (mounted) setState(() => _currency = currency);
    } catch (_) {
      if (mounted) setState(() => _error = GarageUiText.get('quoteCurrencyBlocked'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _publish() async {
    if (_loading || _publishing || _uncertain || _published != null ||
        _currency == null) return;
    final currency = _currency!.code;
    List<GarageQuoteDraftLine> lines;
    try {
      lines = _lines.map((line) => line.toLine(currency)).toList(growable: false);
      GarageWorkshopQuotePublisher.payload(currency: currency, lines: lines);
    } catch (_) {
      setState(() => _error = GarageUiText.get('quoteInvalidLines'));
      return;
    }
    final total = lines.fold<int>(0, (sum, line) =>
      sum + line.quantity * line.unitPriceMinor + line.taxMinor);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(GarageUiText.get('quotePublishQuestion')),
        content: Text(GarageUiText.format('quoteConfirmTotals', {
          'count': lines.length,
          'total': GarageCurrencies.formatMinor(currency, total),
        })),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(GarageUiText.get('quoteBack'))),
          FilledButton(key: const Key('garage_editor_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(GarageUiText.get('quotePublish'))),
        ],
      ),
    );
    if (!mounted || accepted != true || _publishing) return;
    setState(() { _publishing = true; _error = null; });
    try {
      final revision = await widget.publish(currency, lines);
      if (mounted) setState(() => _published = revision);
    } catch (_) {
      // Network failure can occur *after* the server committed. Retrying here
      // could create a second revision and invalidate existing approval.
      if (mounted) setState(() {
        _uncertain = true;
        _error = GarageUiText.get('quoteUncertain');
      });
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Widget _lineForm(_QuoteDraft draft, int index, String currency) =>
      Card(key: Key('quote_draft_$index'),
        child: Padding(padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(GarageUiText.format('itemNumber', {'number': index + 1}),
                  style: Theme.of(context).textTheme.titleMedium)),
                if (_lines.length > 1) IconButton(
                  key: Key('quote_remove_$index'),
                  onPressed: () => setState(() {
                    _lines.removeAt(index); draft.dispose();
                  }),
                  icon: const Icon(Icons.delete_outline)),
              ]),
              DropdownButtonFormField<String>(
                key: Key('quote_type_$index'),
                initialValue: draft.type,
                isExpanded: true,
                decoration: InputDecoration(labelText: GarageUiText.get('quoteType')),
                items: [
                   DropdownMenuItem(value: 'labour', child: Text(GarageUiText.get('quoteLabour'))),
                   DropdownMenuItem(value: 'part', child: Text(GarageUiText.get('quotePart'))),
                   DropdownMenuItem(value: 'other', child: Text(GarageUiText.get('quoteOther'))),
                 ],
                onChanged: (v) { if (v != null) draft.type = v; },
              ),
              TextField(controller: draft.description,
                key: Key('quote_description_$index'),
                maxLength: 500, decoration: InputDecoration(
                  labelText: GarageUiText.get('quoteDescription'))),
              TextField(controller: draft.quantity,
                key: Key('quote_quantity_$index'),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: GarageUiText.get('quoteQuantity'))),
              TextField(controller: draft.unitPrice,
                key: Key('quote_unit_$index'),
                keyboardType: const TextInputType.numberWithOptions(decimal:true),
                decoration: InputDecoration(labelText: GarageUiText.format('quoteUnitPrice', {'currency': currency}))),
              TextField(controller: draft.tax,
                key: Key('quote_tax_$index'),
                keyboardType: const TextInputType.numberWithOptions(decimal:true),
                decoration: InputDecoration(labelText: GarageUiText.format('quoteLineTax', {'currency': currency}))),
            ])));

  @override
  Widget build(BuildContext context) {
    final currency = _currency;
    return Scaffold(
      appBar: AppBar(title: Text(GarageUiText.get('newEstimate'))),
      body: SafeArea(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 112), children: [
          Text(widget.order.complaint,
            style: Theme.of(context).textTheme.titleMedium),
          if (_error != null) Text(_error!, key: const Key('quote_editor_error')),
          if (_published != null) ...[
            Text(GarageUiText.format('quotePublishedStatus', {'revision': _published!}),
              key: const Key('quote_editor_success')),
            FilledButton(onPressed: () => Navigator.pop(context),
              child: Text(GarageUiText.get('quoteBackToOrders'))),
          ] else if (currency != null && !_uncertain) ...[
            if (currency.locked)
              Text(GarageUiText.format('quoteCurrencyLocked', {'currency': currency.code}))
            else GarageQuoteCurrencyPicker(
              currency: currency.code,
              onChanged: (v) => setState(() => _currency =
                GarageQuoteCurrencySelection(v, locked: false))),
            for (var i = 0; i < _lines.length; i++)
              _lineForm(_lines[i], i, currency.code),
            OutlinedButton.icon(
              key: const Key('quote_add_line'),
              onPressed: _publishing || _lines.length >= 50 ? null :
                () => setState(() => _lines.add(_QuoteDraft())),
              icon: const Icon(Icons.add), label: Text(GarageUiText.get('addQuoteItem'))),
            const SizedBox(height: 12),
            FilledButton(key: const Key('quote_publish'),
              onPressed: _publishing ? null : _publish,
              child: Text(_publishing ? GarageUiText.get('quotePublishing') :
                GarageUiText.get('publishEstimate'))),
          ],
        ])),
    );
  }
}
