import 'package:flutter/material.dart';

import 'garage_ui_text.dart';
import 'customer_quote_repository.dart';

/// Revision-aware estimate review shared by QA private-customer and Fleet flows.
/// The caller binds the appropriate independently authorized repository/RPC.
/// Fleet approval never uses the private-customer email authorization endpoint.
class GarageCustomerQuoteScreen extends StatefulWidget {
  const GarageCustomerQuoteScreen({
    required this.loadQuote,
    required this.approveRevision,
    super.key,
  });

  final Future<GarageCustomerQuote?> Function() loadQuote;
  final Future<int> Function(int revision) approveRevision;

  @override
  State<GarageCustomerQuoteScreen> createState() =>
      _GarageCustomerQuoteScreenState();
}

class _GarageCustomerQuoteScreenState extends State<GarageCustomerQuoteScreen> {
  GarageCustomerQuote? _quote;
  bool _loading = true;
  bool _approving = false;
  bool _approvalSucceeded = false;
  int? _approvedRevision;
  String? _notice;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant GarageCustomerQuoteScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadQuote != oldWidget.loadQuote ||
        widget.approveRevision != oldWidget.approveRevision) {
      // The callbacks define the authenticated order/scope. Never carry a
      // confirmed revision or in-flight response into a different scope.
      _generation++;
      _approvalSucceeded = false;
      _approvedRevision = null;
      _approving = false;
      _quote = null;
      _refresh();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_approving) return;
    final generation = ++_generation;
    final load = widget.loadQuote;
    setState(() {
      _loading = true;
      _quote = null;
      _notice = null;
    });
    try {
      final quote = await load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _quote = quote;
        // Do not replay an already accepted revision after a stale read.
        // This marker is reset on account/order scope changes.
        if (quote?.approved == true) _approvedRevision = quote!.revision;
        _approvalSucceeded = quote != null &&
            (quote.approved || quote.revision == _approvedRevision);
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _notice = GarageUiText.get('customerLoadFailed');
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  bool _sameQuote(GarageCustomerQuote previous, GarageCustomerQuote current) {
    if (previous.revision != current.revision ||
        previous.currency != current.currency ||
        previous.approved != current.approved ||
        previous.subtotalMinor != current.subtotalMinor ||
        previous.taxMinor != current.taxMinor ||
        previous.totalMinor != current.totalMinor ||
        previous.lines.length != current.lines.length) {
      return false;
    }
    for (var i = 0; i < previous.lines.length; i++) {
      final a = previous.lines[i];
      final b = current.lines[i];
      if (a.type != b.type ||
          a.description != b.description ||
          a.quantity != b.quantity ||
          a.unitPriceMinor != b.unitPriceMinor ||
          a.taxMinor != b.taxMinor) {
        return false;
      }
    }
    return true;
  }

  Future<void> _requestApproval() async {
    final selected = _quote;
    if (_loading || _approving || _approvalSucceeded ||
        selected == null || selected.approved) {
      return;
    }
    final generation = _generation;
    final load = widget.loadQuote;
    final approve = widget.approveRevision;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(GarageUiText.get('customerConfirm')),
        content: Text(
          GarageUiText.format('customerConfirmBody', {
            'revision': selected.revision,
            'total': selected.formatMinor(selected.totalMinor),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(GarageUiText.get('customerCancel')),
          ),
          FilledButton(
            key: const Key('garage_quote_confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(GarageUiText.get('customerApprove')),
          ),
        ],
      ),
    );
    if (!mounted || generation != _generation || accepted != true || _approving) return;
    setState(() {
      _approving = true;
      _notice = null;
    });
    try {
      // TOCTOU guard: refresh before approval. Server independently locks the
      // order and refuses stale revisions or unauthorized callers.
      final latest = await load();
      if (!mounted || generation != _generation) return;
      if (latest == null || !_sameQuote(selected, latest)) {
        setState(() {
          _quote = latest;
          _notice = GarageUiText.get('customerChanged');
        });
        return;
      }
      final acceptedRevision = await approve(selected.revision);
      if (!mounted || generation != _generation) return;
      if (acceptedRevision != selected.revision) {
        throw const FormatException('Unexpected approved revision');
      }
      setState(() {
        _approvalSucceeded = true;
        _approvedRevision = selected.revision;
        _notice = GarageUiText.get('customerRecorded');
      });
      try {
        final confirmed = await load();
        if (!mounted || generation != _generation) return;
        setState(() {
          _quote = confirmed;
          if (confirmed?.approved == true) {
            _notice = GarageUiText.get('customerApprovedMessage');
          }
        });
      } catch (_) {
        // Successful server RPC is not replayed just because re-fetch failed.
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _quote = null; // Never show stale approval state as actionable.
        _notice = GarageUiText.get('customerApprovalUncertain');
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _approving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    final canApprove = !_loading && !_approving && !_approvalSucceeded &&
        quote != null && !quote.approved;
    final style = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(GarageUiText.get('customerEstimateTitle')),
        actions: [
          IconButton(
            key: const Key('garage_quote_refresh'),
            tooltip: GarageUiText.get('refresh'),
            onPressed: _loading || _approving ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_notice != null) ...[
                    Text(
                      _notice!,
                      key: const Key('garage_quote_notice'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (quote == null) ...[
                    Text(
                      GarageUiText.get('customerEmpty'),
                      key: const Key('garage_quote_empty'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _refresh,
                      child: Text(GarageUiText.get('customerRetry')),
                    ),
                  ] else ...[
                    Text(
                      GarageUiText.format('customerRevision', {'revision': quote.revision}),
                      key: const Key('garage_quote_revision'),
                      style: style.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      quote.approved || _approvalSucceeded
                          ? GarageUiText.get('customerApproved')
                          : GarageUiText.get('customerPending'),
                      key: const Key('garage_quote_status'),
                    ),
                    const SizedBox(height: 16),
                    ...quote.lines.asMap().entries.map((entry) {
                      final line = entry.value;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.description,
                                  style: style.titleMedium),
                              const SizedBox(height: 6),
                              Text(
                                '${line.quantity} × '
                                '${quote.formatMinor(line.unitPriceMinor)}',
                              ),
                              Text(
                                GarageUiText.get('customerTax') +
                                    ': ${quote.formatMinor(line.taxMinor)}',
                              ),
                              Text(
                                quote.formatMinor(line.totalMinor),
                                key: Key('garage_quote_line_${entry.key}'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    Text(
                      GarageUiText.get('customerSubtotal') +
                          ': ${quote.formatMinor(quote.subtotalMinor)}',
                    ),
                    Text(
                      GarageUiText.get('customerTotalTax') +
                          ': ${quote.formatMinor(quote.taxMinor)}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      GarageUiText.get('customerTotal') +
                          ': ${quote.formatMinor(quote.totalMinor)}',
                      key: const Key('garage_quote_total'),
                      style: style.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('garage_quote_approve'),
                      onPressed: canApprove ? _requestApproval : null,
                      child: Text(
                        _approving
                            ? GarageUiText.get('customerApproving')
                            : GarageUiText.get('customerApprove'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      GarageUiText.get('customerScopeWarning'),
                      style: style.bodySmall,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
