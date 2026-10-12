import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization.dart';
import '../data/models.dart';

class BusinessVerificationScreen extends StatefulWidget {
  const BusinessVerificationScreen({required this.company, super.key});

  final CompanyMembership company;

  @override
  State<BusinessVerificationScreen> createState() =>
      _BusinessVerificationScreenState();
}

class _BusinessVerificationScreenState
    extends State<BusinessVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final field in [
      'legal_name',
      'registration_number',
      'vat_number',
      'billing_address_line1',
      'billing_address_line2',
      'billing_city',
      'billing_region',
      'billing_postcode',
      'business_activity',
      'evidence_reference',
    ])
      field: TextEditingController(),
  };

  bool _loading = true;
  bool _saving = false;
  bool _exists = false;
  bool _attested = false;
  String _country = '';
  String _status = 'not_submitted';
  String? _reviewNote;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final id = widget.company.companyId;
      final company = await client
          .from('companies')
          .select('country')
          .eq('id', id)
          .single();
      final profile = await client
          .from('flotaryx_business_profiles')
          .select()
          .eq('company_id', id)
          .maybeSingle();
      final review = await client
          .from('flotaryx_business_reviews')
          .select('status,review_note')
          .eq('company_id', id)
          .maybeSingle();
      if (!mounted) return;
      for (final field in _fields.keys) {
        _fields[field]!.text = profile?[field]?.toString() ?? '';
      }
      setState(() {
        _country = (company['country']?.toString() ?? '').trim().toUpperCase();
        _exists = profile != null;
        _attested = profile?['business_use_attested'] == true;
        _status = review?['status']?.toString() ?? 'not_submitted';
        _reviewNote = review?['review_note']?.toString();
      });
    } catch (_) {
      if (mounted) setState(() => _error = tr('business_profile_failed'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(
    String field,
    String label, {
    bool mandatory = false,
    int minLength = 1,
    int maxLength = 150,
    bool multiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: _fields[field],
        maxLength: maxLength,
        maxLines: multiline ? 3 : 1,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          final text = (value ?? '').trim();
          if (mandatory && text.length < minLength) {
            return tr('business_profile_required');
          }
          return null;
        },
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (!_attested) {
      setState(() => _error = tr('business_profile_attestation_required'));
      return;
    }
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(_country)) {
      setState(() => _error = tr('business_profile_country_invalid'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final values = <String, dynamic>{
        for (final field in _fields.keys)
          field: _fields[field]!.text.trim().isEmpty
              ? null
              : _fields[field]!.text.trim(),
        'business_country': _country,
        'business_use_attested': true,
      };
      if (_exists) {
        await client
            .from('flotaryx_business_profiles')
            .update(values)
            .eq('company_id', widget.company.companyId);
      } else {
        await client.from('flotaryx_business_profiles').insert({
          'company_id': widget.company.companyId,
          ...values,
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('business_profile_saved'))));
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = tr('business_profile_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _statusLabel {
    const labels = {
      'not_submitted': 'business_profile_status_none',
      'pending': 'business_profile_status_pending',
      'needs_info': 'business_profile_status_needs_info',
      'verified': 'business_profile_status_verified',
      'rejected': 'business_profile_status_rejected',
    };
    return tr(labels[_status] ?? 'business_profile_status_pending');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('business_profile_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(tr('business_profile_subtitle')),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _statusLabel,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (_reviewNote != null &&
                                _reviewNote!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${tr('business_profile_review_note')}: $_reviewNote',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InputDecorator(
                            decoration: InputDecoration(
                              labelText: tr('business_profile_country'),
                              border: const OutlineInputBorder(),
                            ),
                            child: Text(_country),
                          ),
                          const SizedBox(height: 14),
                          _field(
                            'legal_name',
                            tr('business_profile_legal'),
                            mandatory: true,
                            minLength: 2,
                            maxLength: 200,
                          ),
                          _field(
                            'registration_number',
                            tr('business_profile_reg'),
                            maxLength: 100,
                          ),
                          _field(
                            'vat_number',
                            tr('business_profile_vat'),
                            maxLength: 50,
                          ),
                          Text(tr('business_profile_vat_optional')),
                          const SizedBox(height: 14),
                          _field(
                            'billing_address_line1',
                            tr('business_profile_address1'),
                            mandatory: true,
                            minLength: 3,
                            maxLength: 300,
                          ),
                          _field(
                            'billing_address_line2',
                            tr('business_profile_address2'),
                            maxLength: 300,
                          ),
                          _field(
                            'billing_city',
                            tr('business_profile_city'),
                            mandatory: true,
                            minLength: 2,
                            maxLength: 150,
                          ),
                          _field(
                            'billing_region',
                            tr('business_profile_region'),
                            maxLength: 150,
                          ),
                          _field(
                            'billing_postcode',
                            tr('business_profile_postcode'),
                            mandatory: true,
                            minLength: 2,
                            maxLength: 30,
                          ),
                          _field(
                            'business_activity',
                            tr('business_profile_activity'),
                            maxLength: 800,
                            multiline: true,
                          ),
                          _field(
                            'evidence_reference',
                            tr('business_profile_evidence'),
                            maxLength: 1000,
                            multiline: true,
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(tr('b2b_confirmation')),
                            value: _attested,
                            onChanged: _saving
                                ? null
                                : (value) => setState(
                                    () => _attested = value ?? false,
                                  ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.verified_outlined),
                            label: Text(
                              tr(
                                _saving
                                    ? 'business_profile_saving'
                                    : 'business_profile_submit',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
