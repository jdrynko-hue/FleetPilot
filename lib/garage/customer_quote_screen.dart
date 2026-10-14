import 'package:flutter/material.dart';

import '../core/localization.dart';
import 'customer_quote_repository.dart';

/// Private-individual customer's Garage quote screen.
///
/// The caller supplies an authenticated GarageCustomerQuoteRepository.load
/// and .approve binding. This screen is NOT available in the public Fleet UI
/// until Garage is safely deployed. Corporate/fleet authorization has a
/// different, not-yet-built consent flow.
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

  bool get _polish => AppLocale.language.value == 'pl';
  String _tr(String pl, String en) => _polish ? pl : en;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_approving) return;
    setState(() {
      _loading = true;
      _quote = null;
      _notice = null;
    });
    try {
      final quote = await widget.loadQuote();
      if (!mounted) return;
      setState(() {
        _quote = quote;
        // If the approval RPC already succeeded, do not allow an immediate
        // duplicate submission just because a later read is temporarily
        // stale. A *new* quote revision is independently approvable.
        if (quote?.approved == true) _approvedRevision = quote!.revision;
        _approvalSucceeded = quote != null &&
            (quote.approved || quote.revision == _approvedRevision);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notice = _tr(
          'Nie udało się bezpiecznie pobrać wyceny. Spróbuj ponownie.',
          'Could not securely load this estimate. Please retry.',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('Potwierdź wycenę', 'Approve estimate')),
        content: Text(
          _tr(
            'Czy akceptujesz wycenę nr ${selected.revision} na kwotę '
                '${selected.formatMinor(selected.totalMinor)}? '
                'To zgoda na wykonanie prac zgodnych z tą wersją.',
            'Do you approve estimate revision ${selected.revision} '
                'totalling ${selected.formatMinor(selected.totalMinor)}? '
                'This authorizes the work described in this revision.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('Anuluj', 'Cancel')),
          ),
          FilledButton(
            key: const Key('garage_quote_confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('Zatwierdź wycenę', 'Approve estimate')),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true || _approving) return;
    setState(() {
      _approving = true;
      _notice = null;
    });
    try {
      // TOCTOU guard: refresh before approval. Server independently locks the
      // order and refuses stale revisions or unauthorized callers.
      final latest = await widget.loadQuote();
      if (!mounted) return;
      if (latest == null || !_sameQuote(selected, latest)) {
        setState(() {
          _quote = latest;
          _notice = _tr(
            'Wycena została zmieniona. Sprawdź aktualną wersję przed zgodą.',
            'The estimate changed. Review the latest revision before approval.',
          );
        });
        return;
      }
      final acceptedRevision = await widget.approveRevision(selected.revision);
      if (!mounted) return;
      if (acceptedRevision != selected.revision) {
        throw const FormatException('Unexpected approved revision');
      }
      setState(() {
        _approvalSucceeded = true;
        _approvedRevision = selected.revision;
        _notice = _tr(
          'Zgoda została zapisana. Odśwież, aby potwierdzić status.',
          'Approval recorded. Refresh to verify the current status.',
        );
      });
      try {
        final confirmed = await widget.loadQuote();
        if (!mounted) return;
        setState(() {
          _quote = confirmed;
          if (confirmed?.approved == true) {
            _notice = _tr(
              'Wycena została zatwierdzona.',
              'Estimate approved successfully.',
            );
          }
        });
      } catch (_) {
        // Successful server RPC is not replayed just because re-fetch failed.
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _quote = null; // Never show stale approval state as actionable.
        _notice = _tr(
          'Nie udało się potwierdzić zgody. Odśwież stan wyceny.',
          'Could not confirm approval. Refresh the estimate before retrying.',
        );
      });
    } finally {
      if (mounted) setState(() => _approving = false);
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
        title: Text(_tr('Wycena naprawy', 'Repair estimate')),
        actions: [
          IconButton(
            key: const Key('garage_quote_refresh'),
            tooltip: _tr('Odśwież', 'Refresh'),
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
                      _tr(
                        'Nie ma aktualnej wyceny do wyświetlenia.',
                        'No current estimate to display.',
                      ),
                      key: const Key('garage_quote_empty'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _refresh,
                      child: Text(_tr('Spróbuj ponownie', 'Try again')),
                    ),
                  ] else ...[
                    Text(
                      _tr(
                        'Wersja ${quote.revision}',
                        'Revision ${quote.revision}',
                      ),
                      key: const Key('garage_quote_revision'),
                      style: style.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      quote.approved || _approvalSucceeded
                          ? _tr('Zatwierdzona', 'Approved')
                          : _tr('Oczekuje na zgodę', 'Awaiting approval'),
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
                                _tr('Podatek', 'Tax') +
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
                      _tr('Kwota netto', 'Subtotal') +
                          ': ${quote.formatMinor(quote.subtotalMinor)}',
                    ),
                    Text(
                      _tr('Podatek łącznie', 'Total tax') +
                          ': ${quote.formatMinor(quote.taxMinor)}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _tr('Łącznie', 'Total') +
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
                            ? _tr('Zatwierdzanie…', 'Approving…')
                            : _tr('Zatwierdź wycenę', 'Approve estimate'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _tr(
                        'Zatwierdzenie dotyczy tylko podanej wersji '
                            'kosztorysu. Zmiana ceny wymaga nowej zgody.',
                        'Approval applies only to this estimate revision. '
                            'Any changed quote requires fresh approval.',
                      ),
                      style: style.bodySmall,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
