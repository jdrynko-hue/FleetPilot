import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization.dart';
import 'operator_session_guard.dart';

class BusinessReviewConsoleScreen extends StatefulWidget {
  const BusinessReviewConsoleScreen({super.key});

  @override
  State<BusinessReviewConsoleScreen> createState() =>
      _BusinessReviewConsoleScreenState();
}

class _BusinessReviewConsoleScreenState
    extends State<BusinessReviewConsoleScreen> {
  String _filter = 'pending';
  bool _working = false;
  late Future<List<Map<String, dynamic>>> _reviews;

  bool get _pl => AppLocale.language.value == 'pl';
  String _t(String pl, String en) => _pl ? pl : en;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _reviews = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final client = Supabase.instance.client;
    final filter = _filter;
    final data = await OperatorSessionGuard(client).run(() => client.rpc(
      'flotaryx_operator_list_reviews',
      params: {'p_status': filter},
    ));
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  void _reload() => setState(_refresh);

  String _state(String code) {
    switch (code) {
      case 'pending':
        return _t('Oczekuje', 'Pending');
      case 'needs_info':
        return _t('Brak danych', 'Needs information');
      case 'verified':
        return _t('Zweryfikowana', 'Verified');
      case 'rejected':
        return _t('Odrzucona', 'Rejected');
      default:
        return code;
    }
  }

  String _field(Map<String, dynamic> row, String key) {
    final value = row[key]?.toString().trim() ?? '';
    return value.isEmpty ? _t('Nie podano', 'Not supplied') : value;
  }

  Widget _info(Map<String, dynamic> row, String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          SelectableText(_field(row, key)),
        ],
      ),
    );
  }

  Future<void> _decide(Map<String, dynamic> row, String nextStatus) async {
    if (_working) return;
    final note = TextEditingController();
    final reference = TextEditingController();
    String method = 'business_registry';
    final approved = nextStatus == 'verified';
    try {
      final answer = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, refreshDialog) => AlertDialog(
            title: Text(
              approved
                  ? _t(
                      'Zatwierdź firmę po weryfikacji',
                      'Approve verified business',
                    )
                  : nextStatus == 'needs_info'
                  ? _t('Poproś o dodatkowe dane', 'Request more information')
                  : _t('Odrzuć zgłoszenie', 'Reject submission'),
            ),
            content: SizedBox(
              width: 470,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_field(row, 'legal_name')),
                    const SizedBox(height: 12),
                    if (approved) ...[
                      Text(
                        _t(
                          'Zatwierdź tylko po samodzielnym sprawdzeniu dokumentów lub oficjalnego rejestru. Numer VAT nie jest wymagany.',
                          'Approve only after independently checking documents or an official registry. A VAT number is optional.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: method,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: _t(
                            'Metoda weryfikacji',
                            'Verification method',
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'business_registry',
                            child: Text(
                              _t('Rejestr firm', 'Business registry'),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'vat_registry',
                            child: Text(_t('Rejestr VAT', 'VAT registry')),
                          ),
                          DropdownMenuItem(
                            value: 'other_documents',
                            child: Text(
                              _t('Inne dokumenty', 'Other documents'),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null)
                            refreshDialog(() => method = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reference,
                        maxLength: 1000,
                        maxLines: 2,
                        onChanged: (_) => refreshDialog(() {}),
                        decoration: InputDecoration(
                          labelText: _t(
                            'Sprawdzone źródło / numer',
                            'Checked source / reference',
                          ),
                          helperText: _t(
                            'Wymagane: minimum 6 znaków',
                            'Required: at least 6 characters',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: note,
                      maxLength: 2000,
                      maxLines: 3,
                      onChanged: (_) => refreshDialog(() {}),
                      decoration: InputDecoration(
                        labelText: _t(
                          'Uzasadnienie decyzji',
                          'Review decision notes',
                        ),
                        helperText: _t(
                          'Wymagane: minimum 5 znaków',
                          'Required: at least 5 characters',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_t('Anuluj', 'Cancel')),
              ),
              FilledButton(
                onPressed: note.text.trim().length >= 5 &&
                        (!approved || reference.text.trim().length >= 6)
                    ? () {
                        final memo = note.text.trim();
                        final ref = reference.text.trim();
                        Navigator.pop(dialogContext, {
                          'note': memo,
                          'method': approved ? method : '',
                          'reference': approved ? ref : '',
                        });
                      }
                    : null,
                child: Text(
                  approved
                      ? _t('Potwierdź weryfikację', 'Confirm verification')
                      : _t('Zapisz decyzję', 'Save decision'),
                ),
              ),
            ],
          ),
        ),
      );
      if (answer == null || !mounted) return;
      setState(() => _working = true);
      try {
        final client = Supabase.instance.client;
        await OperatorSessionGuard(client).run(() => client.rpc(
          'flotaryx_operator_review',
          params: {
            'p_company_id': row['company_id'],
            'p_status': nextStatus,
            'p_note': answer['note'],
            'p_method': answer['method'],
            'p_reference': answer['reference'],
            'p_expected_profile_updated_at': row['profile_updated_at'],
            'p_expected_review_updated_at': row['review_updated_at'],
          },
        ));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('Decyzja zapisana.', 'Decision saved.'))),
        );
        _reload();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Nie zapisano decyzji. Odśwież zgłoszenie i sprawdź wymagane dane.',
                'Could not save decision. Refresh the submission and check required details.',
              ),
            ),
          ),
        );
        _reload();
      } finally {
        if (mounted) setState(() => _working = false);
      }
    } finally {
      note.dispose();
      reference.dispose();
    }
  }

  Future<void> _details(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_field(row, 'legal_name')),
        content: SizedBox(
          width: 530,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_t('Status', 'Status')}: ${_state(_field(row, 'status'))}',
                ),
                const SizedBox(height: 12),
                _info(row, _t('Nazwa konta', 'Workspace name'), 'company_name'),
                _info(row, _t('Kraj', 'Country'), 'business_country'),
                _info(
                  row,
                  _t('Numer rejestrowy', 'Registration number'),
                  'registration_number',
                ),
                _info(row, _t('Numer VAT', 'VAT number'), 'vat_number'),
                _info(
                  row,
                  _t('Ulica', 'Address line 1'),
                  'billing_address_line1',
                ),
                _info(
                  row,
                  _t('Adres 2', 'Address line 2'),
                  'billing_address_line2',
                ),
                _info(row, _t('Miasto', 'City'), 'billing_city'),
                _info(row, _t('Region', 'Region'), 'billing_region'),
                _info(row, _t('Kod pocztowy', 'Postcode'), 'billing_postcode'),
                _info(
                  row,
                  _t('Działalność', 'Business activity'),
                  'business_activity',
                ),
                _info(
                  row,
                  _t('Dowody działalności', 'Business evidence'),
                  'evidence_reference',
                ),
                _info(
                  row,
                  _t('Uwagi weryfikatora', 'Reviewer notes'),
                  'review_note',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('Zamknij', 'Close')),
          ),
          TextButton(
            onPressed: _working
                ? null
                : () {
                    Navigator.pop(ctx);
                    _decide(row, 'needs_info');
                  },
            child: Text(_t('Potrzebne dane', 'Needs info')),
          ),
          TextButton(
            onPressed: _working
                ? null
                : () {
                    Navigator.pop(ctx);
                    _decide(row, 'rejected');
                  },
            child: Text(_t('Odrzuć', 'Reject')),
          ),
          FilledButton(
            onPressed: _working
                ? null
                : () {
                    Navigator.pop(ctx);
                    _decide(row, 'verified');
                  },
            child: Text(_t('Weryfikuj', 'Verify')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t('Panel weryfikacji firm', 'Business verification console'),
        ),
        actions: [
          IconButton(
            tooltip: _t('Odśwież', 'Refresh'),
            onPressed: _working ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  initialValue: _filter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _t('Pokaż zgłoszenia', 'Show submissions'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text(_state('pending')),
                    ),
                    DropdownMenuItem(
                      value: 'needs_info',
                      child: Text(_state('needs_info')),
                    ),
                    DropdownMenuItem(
                      value: 'verified',
                      child: Text(_state('verified')),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text(_state('rejected')),
                    ),
                    DropdownMenuItem(
                      value: 'all',
                      child: Text(_t('Wszystkie', 'All')),
                    ),
                  ],
                  onChanged: _working
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _filter = value;
                            _refresh();
                          });
                        },
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _reviews,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _t(
                              'Nie można pobrać listy. Sprawdź uprawnienia operatora.',
                              'Unable to load submissions. Check operator permissions.',
                            ),
                          ),
                        ),
                      );
                    }
                    final rows = snapshot.data ?? [];
                    if (rows.isEmpty) {
                      return Center(
                        child: Text(_t('Brak zgłoszeń.', 'No submissions.')),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.business_outlined),
                            title: Text(_field(row, 'legal_name')),
                            subtitle: Text(
                              '${_field(row, 'business_country')} · ${_state(_field(row, 'status'))}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _working ? null : () => _details(row),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
