import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';

class RepairFormScreen extends StatefulWidget {
  const RepairFormScreen({
    required this.company,
    this.repair,
    this.initialVehicleId,
    super.key,
  });

  final CompanyMembership company;
  final Repair? repair;
  final String? initialVehicleId;

  @override
  State<RepairFormScreen> createState() => _RepairFormScreenState();
}

class _RepairFormScreenState extends State<RepairFormScreen> {
  final _repository = FleetRepository();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _mileage;
  late final TextEditingController _parts;
  late final TextEditingController _labour;
  late final TextEditingController _other;
  late final TextEditingController _invoice;
  late final TextEditingController _notes;
  List<Vehicle> _vehicles = [];
  List<Garage> _garages = [];
  List<FleetIssue> _issues = [];
  String? _vehicleId;
  String? _garageId;
  String? _issueId;
  String _status = 'planned';
  DateTime? _bookedAt;
  DateTime? _startedAt;
  DateTime? _expectedAt;
  DateTime? _completedAt;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final r = widget.repair;
    _description = TextEditingController(text: r?.description ?? '');
    _mileage = TextEditingController(text: r?.mileageIn?.toString() ?? '');
    _parts = TextEditingController(
      text: r == null ? '' : r.partsCost.toStringAsFixed(2),
    );
    _labour = TextEditingController(
      text: r == null ? '' : r.labourCost.toStringAsFixed(2),
    );
    _other = TextEditingController(
      text: r == null ? '' : r.otherCost.toStringAsFixed(2),
    );
    _invoice = TextEditingController(text: r?.invoiceReference ?? '');
    _notes = TextEditingController(text: r?.notes ?? '');
    _vehicleId = r?.vehicleId ?? widget.initialVehicleId;
    _garageId = r?.garageId;
    _issueId = r?.issueId;
    _status = r?.status ?? 'planned';
    _bookedAt = r?.bookedAt;
    _startedAt = r?.startedAt;
    _expectedAt = r?.expectedCompletionAt;
    _completedAt = r?.completedAt;
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    try {
      final results = await Future.wait([
        _repository.fetchVehicles(widget.company.companyId),
        _repository.fetchGarages(widget.company.companyId),
        _repository.fetchIssues(widget.company.companyId),
      ]);
      if (!mounted) return;
      setState(() {
        _vehicles = results[0] as List<Vehicle>;
        _garages = results[1] as List<Garage>;
        _issues = results[2] as List<FleetIssue>;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [
      _description,
      _mileage,
      _parts,
      _labour,
      _other,
      _invoice,
      _notes,
    ])
      c.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) => showDatePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    initialDate: initial ?? DateTime.now(),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _vehicleId == null) return;
    setState(() => _busy = true);
    final values = <String, dynamic>{
      'company_id': widget.company.companyId,
      'vehicle_id': _vehicleId,
      'issue_id': _issueId,
      'garage_id': _garageId,
      'description': _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      'status': _status,
      'booked_at': _bookedAt?.toUtc().toIso8601String(),
      'started_at': _startedAt?.toUtc().toIso8601String(),
      'expected_completion_at': _expectedAt?.toUtc().toIso8601String(),
      'completed_at': _completedAt?.toUtc().toIso8601String(),
      'mileage_in': parseInt(_mileage.text),
      'parts_cost': parseMoneyInput(_parts.text),
      'labour_cost': parseMoneyInput(_labour.text),
      'other_cost': parseMoneyInput(_other.text),
      'invoice_reference': _invoice.text.trim().isEmpty
          ? null
          : _invoice.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    };
    try {
      if (widget.repair == null) {
        await _repository.createRepair(values);
      } else {
        await _repository.updateRepair(widget.repair!.id, values);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicleIssues = _issues
        .where((i) => _vehicleId == null || i.vehicleId == _vehicleId)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.repair == null ? 'Add repair' : 'Edit repair'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _vehicleId,
              decoration: const InputDecoration(labelText: 'Vehicle *'),
              items: _vehicles
                  .map(
                    (v) => DropdownMenuItem(
                      value: v.id,
                      child: Text(v.registration),
                    ),
                  )
                  .toList(),
              onChanged: widget.repair != null
                  ? null
                  : (value) => setState(() {
                      _vehicleId = value;
                      if (_issueId != null &&
                          !_issues.any(
                            (i) => i.id == _issueId && i.vehicleId == value,
                          ))
                        _issueId = null;
                    }),
              validator: (value) => value == null ? 'Select a vehicle' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Repair description',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: repairStatuses
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(prettifyEnum(s)),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _status = value ?? 'planned'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _garageId,
              decoration: const InputDecoration(labelText: 'Garage'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Not assigned'),
                ),
                ..._garages.map(
                  (g) => DropdownMenuItem<String?>(
                    value: g.id,
                    child: Text(g.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _garageId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: vehicleIssues.any((i) => i.id == _issueId)
                  ? _issueId
                  : null,
              decoration: const InputDecoration(labelText: 'Related issue'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No linked issue'),
                ),
                ...vehicleIssues.map(
                  (i) => DropdownMenuItem<String?>(
                    value: i.id,
                    child: Text(i.title),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _issueId = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mileage,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Mileage in'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _parts,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Parts cost'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _labour,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Labour cost'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _other,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Other cost'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Booked date',
              value: _bookedAt,
              onTap: () async {
                final value = await _pick(_bookedAt);
                if (value != null && mounted) setState(() => _bookedAt = value);
              },
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Started date',
              value: _startedAt,
              onTap: () async {
                final value = await _pick(_startedAt);
                if (value != null && mounted)
                  setState(() => _startedAt = value);
              },
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Expected completion',
              value: _expectedAt,
              onTap: () async {
                final value = await _pick(_expectedAt);
                if (value != null && mounted)
                  setState(() => _expectedAt = value);
              },
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Completed date',
              value: _completedAt,
              onTap: () async {
                final value = await _pick(_completedAt);
                if (value != null && mounted)
                  setState(() => _completedAt = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invoice,
              decoration: const InputDecoration(labelText: 'Invoice reference'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save repair'),
            ),
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
