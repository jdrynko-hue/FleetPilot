import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/localization.dart';

import '../data/fleet_repository.dart';

class CreateCompanyScreen extends StatefulWidget {
  const CreateCompanyScreen({required this.onCreated, this.allowCancel = false, super.key});

  final VoidCallback onCreated;
  final bool allowCancel;

  @override
  State<CreateCompanyScreen> createState() => _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends State<CreateCompanyScreen> {
  final _repository = FleetRepository();
  final _name = TextEditingController();
  final _country = TextEditingController(text: 'GB');
  bool _busy = false;
  bool _b2bConfirmed = false;

  // Supported billing markets: GBP (UK), PLN (Poland), EUR (euro-area).
  static const _euroCountries = <String>{
    'AT', 'BE', 'BG', 'HR', 'CY', 'EE', 'FI', 'FR', 'DE', 'GR',
    'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PT', 'SK', 'SI', 'ES',
  };

  String? get _countryCurrency {
    final code = _country.text.trim().toUpperCase();
    if (code == 'GB') return 'GBP';
    if (code == 'PL') return 'PLN';
    if (_euroCountries.contains(code)) return 'EUR';
    return null;
  }

  bool get _canCreate =>
      !_busy && _b2bConfirmed && _name.text.trim().isNotEmpty &&
      _countryCurrency != null;

  @override
  void dispose() {
    _name.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    final currency = _countryCurrency!;
    setState(() => _busy = true);
    try {
      await _repository.createCompany(
        name: _name.text.trim(),
        country: _country.text.trim().toUpperCase(),
        currency: currency,
      );
      widget.onCreated();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
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
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: tr('company_name'),
                      ),
                    ),
                    SizedBox(height: 16),
                    TextField(
                      controller: _country,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 2,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: tr('country_code'),
                        hintText: 'GB',
                        helperText: AppLocale.language.value == 'pl'
                            ? 'Obsługiwane: GB, PL i kraje strefy euro'
                            : 'Supported: GB, PL and euro-area countries',
                      ),
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
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _b2bConfirmed = value ?? false),
                    ),
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
