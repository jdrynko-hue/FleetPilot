import 'package:flutter/material.dart';

import '../core/localization.dart';

import '../data/fleet_repository.dart';

class CreateCompanyScreen extends StatefulWidget {
  const CreateCompanyScreen({required this.onCreated, super.key});

  final VoidCallback onCreated;

  @override
  State<CreateCompanyScreen> createState() => _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends State<CreateCompanyScreen> {
  final _repository = FleetRepository();
  final _name = TextEditingController();
  final _country = TextEditingController(text: 'GB');
  String _currency = 'GBP';
  bool _busy = false;
  bool _b2bConfirmed = false;

  @override
  void dispose() {
    _name.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || !_b2bConfirmed) return;
    setState(() => _busy = true);
    try {
      await _repository.createCompany(
        name: _name.text.trim(),
        country: _country.text.trim().toUpperCase(),
        currency: _currency,
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
                    Text(
                      tr('create_your_fleet'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    SizedBox(height: 8),
                    Text(tr('workspace_message')),
                    SizedBox(height: 24),
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: tr('company_name'),
                      ),
                    ),
                    SizedBox(height: 16),
                    TextField(
                      controller: _country,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: tr('country_code'),
                        hintText: 'GB',
                      ),
                    ),
                    SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _currency,
                      items: [
                        DropdownMenuItem(
                          value: 'GBP',
                          child: Text(tr('currency_gbp')),
                        ),
                        DropdownMenuItem(
                          value: 'EUR',
                          child: Text(tr('currency_eur')),
                        ),
                        DropdownMenuItem(
                          value: 'PLN',
                          child: Text(tr('currency_pln')),
                        ),
                        DropdownMenuItem(
                          value: 'USD',
                          child: Text(tr('currency_usd')),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _currency = value ?? 'GBP'),
                      decoration: InputDecoration(labelText: tr('currency')),
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
                      onPressed: (_busy || !_b2bConfirmed) ? null : _create,
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
