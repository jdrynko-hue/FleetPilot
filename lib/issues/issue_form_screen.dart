import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';

class IssueFormScreen extends StatefulWidget {
  const IssueFormScreen({
    required this.company,
    this.issue,
    this.initialVehicleId,
    super.key,
  });

  final CompanyMembership company;
  final FleetIssue? issue;
  final String? initialVehicleId;

  @override
  State<IssueFormScreen> createState() => _IssueFormScreenState();
}

class _IssueFormScreenState extends State<IssueFormScreen> {
  final _repository = FleetRepository();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _mileage;
  late final TextEditingController _notes;
  List<Vehicle> _vehicles = [];
  List<Driver> _drivers = [];
  String? _vehicleId;
  String? _driverId;
  String _priority = 'medium';
  String _status = 'open';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final i = widget.issue;
    _title = TextEditingController(text: i?.title ?? '');
    _description = TextEditingController(text: i?.description ?? '');
    _mileage = TextEditingController(
      text: i?.mileageAtReport?.toString() ?? '',
    );
    _notes = TextEditingController(text: i?.notes ?? '');
    _vehicleId = i?.vehicleId ?? widget.initialVehicleId;
    _driverId = i?.reportedByDriverId;
    _priority = i?.priority ?? 'medium';
    _status = i?.status ?? 'open';
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    try {
      final results = await Future.wait([
        _repository.fetchVehicles(widget.company.companyId),
        _repository.fetchDrivers(widget.company.companyId),
      ]);
      if (!mounted) return;
      setState(() {
        _vehicles = results[0] as List<Vehicle>;
        _drivers = results[1] as List<Driver>;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _mileage.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _vehicleId == null) return;
    setState(() => _busy = true);
    final values = <String, dynamic>{
      'company_id': widget.company.companyId,
      'vehicle_id': _vehicleId,
      'reported_by_driver_id': _driverId,
      'title': _title.text.trim(),
      'description': _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      'priority': _priority,
      'status': _status,
      'mileage_at_report': parseInt(_mileage.text),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      if (_status == 'resolved' || _status == 'closed')
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (widget.issue == null) {
        await _repository.createIssue(values);
      } else {
        await _repository.updateIssue(widget.issue!.id, values);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.issue == null ? 'Add issue' : 'Edit issue'),
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
              onChanged: widget.issue != null
                  ? null
                  : (value) => setState(() => _vehicleId = value),
              validator: (value) => value == null ? 'Select a vehicle' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Issue title *'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: issuePriorities
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(prettifyEnum(s)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _priority = value ?? 'medium'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: issueStatuses
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(prettifyEnum(s)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _status = value ?? 'open'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _driverId,
              decoration: const InputDecoration(
                labelText: 'Reported by driver',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Not specified'),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _mileage,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Mileage when reported',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Internal notes'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save issue'),
            ),
          ],
        ),
      ),
    );
  }
}
