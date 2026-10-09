import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/formatters.dart';
import '../core/localization.dart';
import '../core/widgets.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import 'check_logic.dart';

/// All reads and writes are additionally scoped and authorized by Supabase RLS.
class VehicleChecksScreen extends StatefulWidget {
  const VehicleChecksScreen({
    required this.company,
    required this.vehicle,
    required this.canManage,
    super.key,
  });

  final CompanyMembership company;
  final Vehicle vehicle;
  final bool canManage;

  @override
  State<VehicleChecksScreen> createState() => _VehicleChecksScreenState();
}

class _VehicleChecksScreenState extends State<VehicleChecksScreen> {
  final FleetRepository _repository = FleetRepository();
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _odometer = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final Map<String, bool?> _answers = {
    for (final item in driverCheckItems) item: null,
  };

  late Future<_VehicleChecksData> _future;
  bool _submitting = false;
  bool _unsafe = false;
  bool _changed = false;
  String _checkType = 'pre_trip';

  @override
  void initState() {
    super.initState();
    _odometer.text = widget.vehicle.mileage > 0
        ? widget.vehicle.mileage.toString()
        : '';
    _reload();
  }

  @override
  void dispose() {
    _odometer.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _reload() {
    _future = _fetch();
  }

  Future<_VehicleChecksData> _fetch() async {
    // Await independently to avoid mixing a Future with Postgrest builders in Future.wait.
    final results = <dynamic>[
      await _repository.fetchCompanyEntitlements(widget.company.companyId),
      await _client
          .from('driver_vehicle_checks')
          .select(
            'id, driver_id, check_type, result, odometer, checks, notes, checked_at',
          )
          .eq('company_id', widget.company.companyId)
          .eq('vehicle_id', widget.vehicle.id)
          .order('checked_at', ascending: false)
          .limit(25),
      await _client
          .from('drivers')
          .select('id, user_id, name, is_active')
          .eq('company_id', widget.company.companyId)
          .eq('is_active', true),
    ];

    final membership = results[0] as CompanyEntitlements;
    final checks = (results[1] as List)
        .map((row) => (row as Map).cast<String, dynamic>())
        .toList();
    final drivers = (results[2] as List)
        .map((row) => (row as Map).cast<String, dynamic>())
        .toList();

    // Managers can inspect the vehicle themselves. A viewer must be linked
    // to the driver currently assigned to the specific vehicle.
    String? linkedDriverId;
    if (!widget.canManage) {
      for (final driver in drivers) {
        if (driver['id'] == widget.vehicle.currentDriverId &&
            driver['user_id'] == _client.auth.currentUser?.id) {
          linkedDriverId = driver['id']?.toString();
          break;
        }
      }
    }

    return _VehicleChecksData(
      entitlement: membership,
      checks: checks,
      drivers: {
        for (final driver in drivers)
          driver['id'].toString(): driver['name'].toString(),
      },
      linkedDriverId: linkedDriverId,
    );
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit(_VehicleChecksData data) async {
    if (_submitting) return;
    final result = driverCheckResult(_answers, unsafe: _unsafe);
    if (result == null) {
      _notify(tr('check_complete_all'));
      return;
    }
    if (result != 'pass' && _notes.text.trim().isEmpty) {
      _notify(tr('check_describe_defect'));
      return;
    }
    final odometerText = _odometer.text.trim();
    if (odometerText.isNotEmpty && int.tryParse(odometerText) == null) {
      _notify(tr('check_invalid_odometer'));
      return;
    }
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      _notify(tr('check_sign_in_again'));
      return;
    }

    setState(() => _submitting = true);
    try {
      await _client.from('driver_vehicle_checks').insert({
        'company_id': widget.company.companyId,
        'vehicle_id': widget.vehicle.id,
        'driver_id': widget.canManage ? null : data.linkedDriverId,
        'created_by': currentUserId,
        'check_type': _checkType,
        'result': result,
        'odometer': odometerText.isEmpty ? null : int.parse(odometerText),
        'checks': {
          for (final entry in _answers.entries) entry.key: entry.value!,
        },
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (!mounted) return;
      _changed = true;
      _notes.clear();
      setState(() {
        _submitting = false;
        _unsafe = false;
        for (final key in driverCheckItems) {
          _answers[key] = null;
        }
        _reload();
      });
      _notify(
        result == 'pass' ? tr('check_saved') : tr('check_defect_created'),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _notify('${tr('check_save_failed')}: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.pop(context, _changed)),
        title: Text(tr('walkaround_checks')),
      ),
      body: FutureBuilder<_VehicleChecksData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              error: snapshot.error!,
              onRetry: () => setState(_reload),
            );
          }

          final data = snapshot.data!;
          final enabled =
              data.entitlement.isAccessActive &&
              data.entitlement.hasFeature('driver_mode');
          final canSubmit =
              enabled && (widget.canManage || data.linkedDriverId != null);
          final completed = _answers.values
              .where((answer) => answer != null)
              .length;
          final hasDefect = _answers.values.contains(false);

          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
              children: [
                Text(
                  widget.vehicle.registration,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(tr('check_intro')),
                const SizedBox(height: 16),
                if (!enabled)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(tr('check_plan_unavailable')),
                    ),
                  )
                else if (!canSubmit)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(tr('check_not_assigned')),
                    ),
                  ),
                if (canSubmit) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _checkType,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: tr('check_type_label'),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'pre_trip',
                                child: Text(tr('check_pre_trip')),
                              ),
                              DropdownMenuItem(
                                value: 'post_trip',
                                child: Text(tr('check_post_trip')),
                              ),
                            ],
                            onChanged: _submitting
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _checkType = value);
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _odometer,
                            enabled: !_submitting,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText: tr('check_odometer'),
                              helperText: tr('check_odometer_optional'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${tr('check_progress')}: $completed / ${driverCheckItems.length}',
                          ),
                          const SizedBox(height: 8),
                          for (final key in driverCheckItems) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr('check_item_$key'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      ChoiceChip(
                                        label: Text(tr('check_ok')),
                                        selected: _answers[key] == true,
                                        onSelected: _submitting
                                            ? null
                                            : (_) => setState(
                                                () => _answers[key] = true,
                                              ),
                                      ),
                                      ChoiceChip(
                                        label: Text(tr('check_fault')),
                                        selected: _answers[key] == false,
                                        onSelected: _submitting
                                            ? null
                                            : (_) => setState(
                                                () => _answers[key] = false,
                                              ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Divider(height: 1),
                          if (hasDefect)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(tr('check_unsafe')),
                              subtitle: Text(tr('check_unsafe_help')),
                              value: _unsafe,
                              onChanged: _submitting
                                  ? null
                                  : (value) => setState(() => _unsafe = value),
                            ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _notes,
                            enabled: !_submitting,
                            maxLines: 3,
                            maxLength: 1000,
                            decoration: InputDecoration(
                              labelText: hasDefect
                                  ? tr('check_defect_notes')
                                  : tr('notes'),
                              hintText: tr('check_notes_hint'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _submitting ? null : () => _submit(data),
                            icon: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.fact_check_outlined),
                            label: Text(tr('check_submit')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  tr('check_history'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (data.checks.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(tr('check_no_history')),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final check in data.checks) ...[
                          ExpansionTile(
                            leading: Icon(
                              check['result'] == 'pass'
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_rounded,
                              color: check['result'] == 'pass'
                                  ? Colors.green
                                  : Colors.deepOrange,
                            ),
                            title: Text(
                              check['result'] == 'pass'
                                  ? tr('check_result_pass')
                                  : check['result'] == 'unsafe'
                                  ? tr('check_result_unsafe')
                                  : tr('check_result_defect'),
                            ),
                            subtitle: Text(
                              [
                                check['check_type'] == 'post_trip'
                                    ? tr('check_post_trip')
                                    : tr('check_pre_trip'),
                                if (DateTime.tryParse(
                                      '${check['checked_at']}',
                                    ) !=
                                    null)
                                  formatDateTime(
                                    DateTime.parse('${check['checked_at']}'),
                                  ),
                                if (data.drivers[check['driver_id']] != null)
                                  data.drivers[check['driver_id']]!,
                              ].join(' • '),
                            ),
                            children: [
                              for (final key in driverCheckItems)
                                ListTile(
                                  dense: true,
                                  title: Text(tr('check_item_$key')),
                                  trailing: Icon(
                                    (check['checks'] as Map?)?[key] == true
                                        ? Icons.check_circle_outline
                                        : Icons.error_outline,
                                  ),
                                ),
                              if (check['odometer'] != null)
                                ListTile(
                                  dense: true,
                                  title: Text(tr('check_odometer')),
                                  trailing: Text('${check['odometer']}'),
                                ),
                              if ('${check['notes'] ?? ''}'.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text('${check['notes']}'),
                                  ),
                                ),
                            ],
                          ),
                          const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VehicleChecksData {
  const _VehicleChecksData({
    required this.entitlement,
    required this.checks,
    required this.drivers,
    required this.linkedDriverId,
  });

  final CompanyEntitlements entitlement;
  final List<Map<String, dynamic>> checks;
  final Map<String, String> drivers;
  final String? linkedDriverId;
}
