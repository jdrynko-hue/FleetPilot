import 'package:flutter/material.dart';

import '../core/localization.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';

class VehicleFormScreen extends StatefulWidget {
  const VehicleFormScreen({required this.company, this.vehicle, super.key});

  final CompanyMembership company;
  final Vehicle? vehicle;

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _repository = FleetRepository();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _registration;
  late final TextEditingController _vin;
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _year;
  late final TextEditingController _mileage;
  late final TextEditingController _inspectionType;
  late final TextEditingController _serviceMileage;
  late final TextEditingController _notes;
  String _status = 'available';
  String? _driverId;
  DateTime? _inspectionDue;
  DateTime? _serviceDue;
  DateTime? _insuranceDue;
  List<Driver> _drivers = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _registration = TextEditingController(text: v?.registration ?? '');
    _vin = TextEditingController(text: v?.vin ?? '');
    _make = TextEditingController(text: v?.make ?? '');
    _model = TextEditingController(text: v?.model ?? '');
    _year = TextEditingController(text: v?.year?.toString() ?? '');
    _mileage = TextEditingController(text: v?.mileage.toString() ?? '0');
    _inspectionType = TextEditingController(text: v?.inspectionType ?? 'MOT');
    _serviceMileage = TextEditingController(
      text: v?.serviceDueMileage?.toString() ?? '',
    );
    _notes = TextEditingController(text: v?.notes ?? '');
    _status = v?.status ?? 'available';
    _driverId = v?.currentDriverId;
    _inspectionDue = v?.inspectionDueDate;
    _serviceDue = v?.serviceDueDate;
    _insuranceDue = v?.insuranceExpiryDate;
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    try {
      final drivers = await _repository.fetchDrivers(widget.company.companyId);
      if (mounted) setState(() => _drivers = drivers);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final controller in [
      _registration,
      _vin,
      _make,
      _model,
      _year,
      _mileage,
      _inspectionType,
      _serviceMileage,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pickDate(DateTime? initial) => showDatePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    initialDate: initial ?? DateTime.now(),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final values = <String, dynamic>{
      'company_id': widget.company.companyId,
      'current_driver_id': _driverId,
      'registration': _registration.text.trim().toUpperCase(),
      'vin': _vin.text.trim().isEmpty ? null : _vin.text.trim().toUpperCase(),
      'make': _make.text.trim().isEmpty ? null : _make.text.trim(),
      'model': _model.text.trim().isEmpty ? null : _model.text.trim(),
      'year': parseInt(_year.text),
      'mileage': parseInt(_mileage.text) ?? 0,
      'status': _status,
      'inspection_type': _inspectionType.text.trim().isEmpty
          ? 'MOT'
          : _inspectionType.text.trim(),
      'inspection_due_date': _inspectionDue?.toIso8601String().split('T').first,
      'service_due_date': _serviceDue?.toIso8601String().split('T').first,
      'service_due_mileage': parseInt(_serviceMileage.text),
      'insurance_expiry_date': _insuranceDue
          ?.toIso8601String()
          .split('T')
          .first,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    };

    try {
      if (widget.vehicle == null) {
        await _repository.createVehicle(values);
      } else {
        await _repository.updateVehicle(widget.vehicle!.id, values);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    if (widget.vehicle == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('archive_vehicle_q')),
        content: Text(tr('archive_vehicle_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('archive')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.archiveVehicle(widget.vehicle!.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.vehicle == null
              ? tr('add_vehicle')
              : widget.vehicle!.registration,
        ),
        actions: [
          if (widget.vehicle != null)
            IconButton(
              onPressed: _busy ? null : _archive,
              tooltip: tr('archive'),
              icon: const Icon(Icons.archive_outlined),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _registration,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tr('registration')),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? tr('registration_required')
                  : null,
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _make,
                    decoration: InputDecoration(labelText: tr('make')),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _model,
                    decoration: InputDecoration(labelText: tr('model')),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('year')),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _mileage,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('mileage')),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _vin,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: 'VIN'),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(labelText: tr('status')),
              items: vehicleStatuses
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(prettifyEnum(s)),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _status = value ?? 'available'),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _driverId,
              decoration: InputDecoration(labelText: tr('assigned_driver')),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(tr('no_driver')),
                ),
                ..._drivers.map(
                  (d) => DropdownMenuItem<String?>(
                    value: d.id,
                    child: Text(d.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _driverId = value),
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _inspectionType,
              decoration: InputDecoration(
                labelText: tr('inspection_type'),
                hintText: 'MOT',
              ),
            ),
            SizedBox(height: 12),
            _DateField(
              label: tr('inspection_due'),
              value: _inspectionDue,
              onTap: () async {
                final value = await _pickDate(_inspectionDue);
                if (value != null && mounted)
                  setState(() => _inspectionDue = value);
              },
            ),
            SizedBox(height: 12),
            _DateField(
              label: tr('service_due_date'),
              value: _serviceDue,
              onTap: () async {
                final value = await _pickDate(_serviceDue);
                if (value != null && mounted)
                  setState(() => _serviceDue = value);
              },
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _serviceMileage,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('service_due_mileage')),
            ),
            SizedBox(height: 12),
            _DateField(
              label: tr('insurance_expiry'),
              value: _insuranceDue,
              onTap: () async {
                final value = await _pickDate(_insuranceDue);
                if (value != null && mounted)
                  setState(() => _insuranceDue = value);
              },
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
              child: Text(_busy ? tr('saving') : tr('save_vehicle')),
            ),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(formatDate(value)),
      ),
    );
  }
}
