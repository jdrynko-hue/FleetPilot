import 'package:flutter/material.dart';

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

  @override
  void dispose() {
    _name.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) return;
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
                      'Utwórz swoją flotę',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This workspace keeps one company’s fleet data isolated from every other company.',
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Nazwa firmy',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _country,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Kod kraju',
                        hintText: 'GB',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _currency,
                      items: const [
                        DropdownMenuItem(
                          value: 'GBP',
                          child: Text('GBP — British pound'),
                        ),
                        DropdownMenuItem(
                          value: 'EUR',
                          child: Text('EUR — Euro'),
                        ),
                        DropdownMenuItem(
                          value: 'PLN',
                          child: Text('PLN — Polish złoty'),
                        ),
                        DropdownMenuItem(
                          value: 'USD',
                          child: Text('USD — US dollar'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _currency = value ?? 'GBP'),
                      decoration: const InputDecoration(labelText: 'Waluta'),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _create,
                      child: Text(_busy ? 'Tworzenie…' : 'Utwórz flotę'),
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
