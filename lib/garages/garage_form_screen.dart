import 'package:flutter/material.dart';

import '../core/localization.dart';

import '../data/fleet_repository.dart';
import '../data/models.dart';

class GarageFormScreen extends StatefulWidget {
  const GarageFormScreen({required this.company, this.garage, super.key});

  final CompanyMembership company;
  final Garage? garage;

  @override
  State<GarageFormScreen> createState() => _GarageFormScreenState();
}

class _GarageFormScreenState extends State<GarageFormScreen> {
  final _repository = FleetRepository();
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> c;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final g = widget.garage;
    c = {
      'name': TextEditingController(text: g?.name ?? ''),
      'contact_name': TextEditingController(text: g?.contactName ?? ''),
      'phone': TextEditingController(text: g?.phone ?? ''),
      'email': TextEditingController(text: g?.email ?? ''),
      'address_line_1': TextEditingController(text: g?.addressLine1 ?? ''),
      'address_line_2': TextEditingController(text: g?.addressLine2 ?? ''),
      'city': TextEditingController(text: g?.city ?? ''),
      'postcode': TextEditingController(text: g?.postcode ?? ''),
      'country': TextEditingController(text: g?.country ?? ''),
      'notes': TextEditingController(text: g?.notes ?? ''),
    };
  }

  @override
  void dispose() {
    for (final controller in c.values) controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final values = <String, dynamic>{'company_id': widget.company.companyId};
    for (final entry in c.entries) {
      values[entry.key] = entry.value.text.trim().isEmpty
          ? null
          : entry.value.text.trim();
    }
    values['name'] = c['name']!.text.trim();
    try {
      if (widget.garage == null) {
        await _repository.createGarage(values);
      } else {
        await _repository.updateGarage(widget.garage!.id, values);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    if (widget.garage == null) return;
    await _repository.archiveGarage(widget.garage!.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.garage == null ? tr('add_garage') : tr('edit_garage'),
        ),
        actions: [
          if (widget.garage != null)
            IconButton(
              onPressed: _archive,
              icon: const Icon(Icons.archive_outlined),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(
              'name',
              tr('garage_name'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? tr('name_required') : null,
            ),
            _field('contact_name', tr('contact_name')),
            _field('phone', tr('phone'), keyboardType: TextInputType.phone),
            _field(
              'email',
              tr('email'),
              keyboardType: TextInputType.emailAddress,
            ),
            _field('address_line_1', tr('address_line_1')),
            _field('address_line_2', tr('address_line_2')),
            Row(
              children: [
                Expanded(child: _field('city', tr('city'))),
                SizedBox(width: 12),
                Expanded(child: _field('postcode', tr('postcode'))),
              ],
            ),
            _field('country', tr('country')),
            TextFormField(
              controller: c['notes'],
              maxLines: 4,
              decoration: InputDecoration(labelText: tr('notes')),
            ),
            SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? tr('saving') : tr('save_garage')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String key,
    String label, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c[key],
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
