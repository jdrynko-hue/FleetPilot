import 'package:flutter/material.dart';

import '../core/localization.dart';
import 'billing_markets.dart';
import 'fleet_creation_notice.dart';

import '../data/fleet_repository.dart';

typedef FleetCreationHandler = Future<void> Function({
  required String name,
  required String country,
  required String currency,
});

class CreateCompanyScreen extends StatefulWidget {
  const CreateCompanyScreen({required this.onCreated, this.allowCancel = false, this.createCompany, this.currentAccountId, super.key});

  final VoidCallback onCreated;
  final bool allowCancel;
  final FleetCreationHandler? createCompany;
  final String? Function()? currentAccountId;

  @override
  State<CreateCompanyScreen> createState() => _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends State<CreateCompanyScreen> {
  final _name = TextEditingController();
  String _country = 'GB';
  bool _busy = false;
  bool _uncertain = false;
  VoidCallback? _checkMemberships;
  bool _b2bConfirmed = false;

  String? get _countryCurrency => currencyForFleetCountry(_country);

  bool get _canCreate =>
      !_busy && !_uncertain && _b2bConfirmed && _name.text.trim().isNotEmpty &&
      _name.text.trim().runes.length <= 160 &&
      _countryCurrency != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    final repository = widget.createCompany == null ? FleetRepository() : null;
    String? accountId() => widget.currentAccountId != null
        ? widget.currentAccountId!()
        : repository?.currentUser?.id;
    final submittingAccount = accountId();
    bool current() => mounted && accountId() == submittingAccount;
    final currency = _countryCurrency!;
    setState(() => _busy = true);
    try {
      if (widget.createCompany != null) {
        await widget.createCompany!(
          name: _name.text.trim(),
          country: _country,
          currency: currency,
        );
      } else {
        await repository!.createCompany(
          name: _name.text.trim(),
          country: _country,
          currency: currency,
        );
      }
      if (current()) widget.onCreated();
    } catch (_) {
      if (!current()) return;
      // The insert may have committed before the response was lost. Both
      // initial and additional setup must check memberships before retrying.
      setState(() {
        _uncertain = true;
        _checkMemberships = () {
          if (current()) widget.onCreated();
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.allowCancel ? AppBar(title: Text(tr('create_your_fleet'))) : null,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.allowCancel) ...[
                      Text(
                        tr('create_your_fleet'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(tr('workspace_message')),
                    SizedBox(height: 24),
                    TextField(
                      controller: _name,
                      enabled: !_busy && !_uncertain,
                      maxLength: 160,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: tr('company_name'),
                      ),
                    ),
                    SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const Key('fleet_country_picker'),
                      initialValue: _country,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: AppLocale.language.value == 'pl'
                            ? 'Kraj rejestracji firmy'
                            : 'Company registration country',
                        border: const OutlineInputBorder(),
                      ),
                      items: supportedFleetCountries.keys
                          .map((code) => DropdownMenuItem<String>(
                                value: code,
                                child: Text(
                                  '${fleetCountryName(code, locale: AppLocale.language.value)} ($code)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: _busy || _uncertain
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _country = value);
                              }
                            },
                    ),
                    SizedBox(height: 16),
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: tr('currency'),
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(
                        switch (_countryCurrency) {
                          'GBP' => tr('currency_gbp'),
                          'PLN' => tr('currency_pln'),
                          'EUR' => tr('currency_eur'),
                          _ => AppLocale.language.value == 'pl'
                              ? 'Nieobsługiwany kraj'
                              : 'Country not supported',
                        },
                      ),
                    ),
                    SizedBox(height: 24),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('b2b_confirmation')),
                      subtitle: Text(tr('b2b_only')),
                      value: _b2bConfirmed,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: _busy || _uncertain
                          ? null
                          : (value) =>
                                setState(() => _b2bConfirmed = value ?? false),
                    ),
                    if (_uncertain) ...[
                      Text(uncertainFleetCreation(), key: const Key('fleet_creation_uncertain')),
                      OutlinedButton(key: const Key('fleet_creation_check_memberships'),
                        onPressed: _busy ? null : _checkMemberships,
                        child: Text(tr('refresh'))),
                    ],
                    FilledButton(
                      onPressed: _canCreate ? _create : null,
                      child: Text(_busy ? tr('creating') : tr('create_fleet')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
