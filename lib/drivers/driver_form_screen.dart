import 'package:flutter/material.dart';

import '../core/localization.dart';

import '../core/constants.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';

class DriverFormScreen extends StatefulWidget {
  const DriverFormScreen({required this.company, this.driver, super.key});

  final CompanyMembership company;
  final Driver? driver;

  @override
  State<DriverFormScreen> createState() => _DriverFormScreenState();
}

class _DriverFormScreenState extends State<DriverFormScreen> {
  final _repository = FleetRepository();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _reference;
  late final TextEditingController _notes;
  String _status = 'active';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final d = widget.driver;
    _name = TextEditingController(text: d?.name ?? '');
    _phone = TextEditingController(text: d?.phone ?? '');
    _email = TextEditingController(text: d?.email ?? '');
    _reference = TextEditingController(text: d?.employeeReference ?? '');
    _notes = TextEditingController(text: d?.notes ?? '');
    _status = d?.status ?? 'active';
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final values = <String, dynamic>{
      'company_id': widget.company.companyId,
      'name': _name.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'employee_reference': _reference.text.trim().isEmpty
          ? null
          : _reference.text.trim(),
      'status': _status,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    };
    try {
      if (widget.driver == null) {
        await _repository.createDriver(values);
      } else {
        await _repository.updateDriver(widget.driver!.id, values);
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
    if (widget.driver == null) return;
    await _repository.archiveDriver(widget.driver!.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.driver == null ? tr('add_driver') : tr('edit_driver'),
        ),
        actions: [
          if (widget.driver != null)
            IconButton(
              onPressed: _archive,
              icon: const Icon(Icons.archive_outlined),
              tooltip: tr('archive'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: tr('name')),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? tr('name_required') : null,
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: tr('phone')),
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: tr('email')),
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _reference,
              decoration: InputDecoration(labelText: tr('employee_reference')),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(labelText: tr('status')),
              items: driverStatuses
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(prettifyEnum(s)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _status = value ?? 'active'),
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 4,
              decoration: InputDecoration(labelText: tr('notes')),
            ),
            SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? tr('saving') : tr('save_driver')),
            ),
          ],
        ),
      ),
    );
  }
}
