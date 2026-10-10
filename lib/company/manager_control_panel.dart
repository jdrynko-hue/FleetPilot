import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../core/localization.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import '../issues/issue_form_screen.dart';
import '../repairs/repair_form_screen.dart';
import 'vehicle_change_requests_screen.dart';

class ManagerControlPanel extends StatefulWidget {
  const ManagerControlPanel({required this.company, super.key});

  final CompanyMembership company;

  @override
  State<ManagerControlPanel> createState() => _ManagerControlPanelState();
}

class _ManagerControlPanelState extends State<ManagerControlPanel> {
  final FleetRepository _repo = FleetRepository();
  final SupabaseClient _client = Supabase.instance.client;
  late Future<_ManagerData> _data;
  bool _saving = false;

  String _t(String pl, String en) => AppLocale.language.value == 'pl' ? pl : en;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _data = _fetch();

  Future<_ManagerData> _fetch() async {
    if (!canManageForRole(widget.company.role)) {
      throw StateError(
        _t('Brak uprawnień managera.', 'Manager access required.'),
      );
    }
    final companyId = widget.company.companyId;
    final vans = await _repo.fetchVehicles(companyId);
    final drivers = await _repo.fetchDrivers(companyId);
    final issues = await _repo.fetchIssues(companyId);
    final repairs = await _repo.fetchRepairs(companyId);
    final changes = await _client.rpc(
      'fleetpilot_list_vehicle_change_requests',
      params: {'_company_id': companyId},
    );
    final requests = (changes as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
    return _ManagerData(
      vehicles: vans,
      drivers: drivers,
      issues: issues,
      repairs: repairs,
      pendingRequests: requests.where((r) => r['status'] == 'pending').length,
    );
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openAddIssue() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => IssueFormScreen(company: widget.company),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _openAddRepair() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RepairFormScreen(company: widget.company),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _reviewRequests() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VehicleChangeRequestsScreen(company: widget.company),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _assign(_ManagerData data, {String? preselectedDriverId}) async {
    if (_saving || data.drivers.isEmpty) return;
    String? driverId = preselectedDriverId;
    String? vehicleId;
    const unassign = '__unassign__';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) {
          final options = data.vehicles.where((vehicle) {
            if (vehicle.currentDriverId == driverId) return true;
            return vehicle.currentDriverId == null &&
                ![
                  'sold',
                  'off_road',
                  'workshop',
                  'maintenance',
                ].contains(vehicle.status);
          }).toList();
          return AlertDialog(
            title: Text(
              _t('Przypisz vana kierowcy', 'Assign a van to a driver'),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _t(
                      'Zmiana zostanie zapisana w historii pojazdu.',
                      'The change will be saved in the vehicle history.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: driverId,
                    decoration: InputDecoration(
                      labelText: _t('Kierowca', 'Driver'),
                    ),
                    items: data.drivers
                        .map(
                          (driver) => DropdownMenuItem(
                            value: driver.id,
                            child: Text(
                              driver.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() {
                      driverId = value;
                      vehicleId = null;
                    }),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey(driverId),
                    isExpanded: true,
                    initialValue: vehicleId,
                    decoration: InputDecoration(
                      labelText: _t('Nowy pojazd', 'New van'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: unassign,
                        child: Text(_t('Odepnij vana', 'Unassign van')),
                      ),
                      ...options.map(
                        (vehicle) => DropdownMenuItem(
                          value: vehicle.id,
                          child: Text(
                            vehicle.registration,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: driverId == null
                        ? null
                        : (value) => update(() => vehicleId = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr('cancel')),
              ),
              FilledButton(
                onPressed: driverId == null || vehicleId == null
                    ? null
                    : () => Navigator.pop(dialogContext, {
                        'driver': driverId!,
                        'vehicle': vehicleId!,
                      }),
                child: Text(_t('Zapisz przypisanie', 'Save assignment')),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    final selectedDriver = data.drivers.firstWhere(
      (d) => d.id == result['driver'],
    );
    final selectedVan = result['vehicle'] == unassign
        ? _t('bez pojazdu', 'no vehicle')
        : data.vehicles
              .firstWhere((v) => v.id == result['vehicle'])
              .registration;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Potwierdź zmianę', 'Confirm assignment')),
        content: Text('${selectedDriver.name} → $selectedVan'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('Potwierdź', 'Confirm')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _client.rpc(
        'fleetpilot_manager_assign_vehicle',
        params: {
          '_company_id': widget.company.companyId,
          '_driver_id': result['driver'],
          '_vehicle_id': result['vehicle'] == unassign
              ? null
              : result['vehicle'],
        },
      );
      if (!mounted) return;
      _notice(_t('Przypisanie pojazdu zapisane.', 'Vehicle assignment saved.'));
      setState(_reload);
    } catch (error) {
      _notice(
        '${_t('Nie udało się zmienić pojazdu', 'Assignment failed')}: $error',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _quickAction(IconData icon, String title, VoidCallback action) =>
      OutlinedButton.icon(
        icon: Icon(icon),
        label: Text(title),
        onPressed: _saving ? null : action,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Panel managera', 'Manager control panel')),
        actions: [
          IconButton(
            tooltip: _t('Odśwież', 'Refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_reload),
          ),
        ],
      ),
      body: FutureBuilder<_ManagerData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => setState(_reload),
                      child: Text(_t('Spróbuj ponownie', 'Try again')),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data!;
          final assigned = data.vehicles
              .where((v) => v.currentDriverId != null)
              .length;
          final openIssues = data.issues
              .where((i) => i.status != 'closed' && i.status != 'resolved')
              .length;
          final openRepairs = data.repairs
              .where((r) => r.status != 'completed' && r.status != 'cancelled')
              .length;
          final scheme = Theme.of(context).colorScheme;
          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _data;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
              children: [
                Text(
                  widget.company.companyName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _stat(
                      _t('Vany', 'Vans'),
                      '${data.vehicles.length}',
                      Icons.local_shipping_outlined,
                    ),
                    _stat(
                      _t('Przydzielone', 'Assigned'),
                      '$assigned',
                      Icons.assignment_turned_in_outlined,
                    ),
                    _stat(
                      _t('Usterki', 'Open defects'),
                      '$openIssues',
                      Icons.report_problem_outlined,
                    ),
                    _stat(
                      _t('Naprawy', 'Open repairs'),
                      '$openRepairs',
                      Icons.build_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  _t('Szybkie działania', 'Quick actions'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _quickAction(
                      Icons.swap_horiz,
                      _t('Zmień vana', 'Change van'),
                      () => _assign(data),
                    ),
                    _quickAction(
                      Icons.add_circle_outline,
                      _t('Dodaj usterkę', 'Add defect'),
                      _openAddIssue,
                    ),
                    _quickAction(
                      Icons.build_circle_outlined,
                      _t('Dodaj naprawę', 'Add repair'),
                      _openAddRepair,
                    ),
                    _quickAction(
                      Icons.fact_check_outlined,
                      _t(
                        'Wnioski (${data.pendingRequests})',
                        'Requests (${data.pendingRequests})',
                      ),
                      _reviewRequests,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  _t('Kierowcy i przypisane vany', 'Drivers and their vans'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (data.drivers.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(_t('Brak kierowców.', 'No drivers yet.')),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < data.drivers.length;
                          index++
                        ) ...[
                          Builder(
                            builder: (context) {
                              final driver = data.drivers[index];
                              Vehicle? van;
                              for (final v in data.vehicles) {
                                if (v.currentDriverId == driver.id) {
                                  van = v;
                                  break;
                                }
                              }
                              return ListTile(
                                leading: Icon(
                                  Icons.person_outline,
                                  color: scheme.primary,
                                ),
                                title: Text(driver.name),
                                subtitle: Text(
                                  van?.registration ??
                                      _t('Nieprzypisany', 'Unassigned'),
                                ),
                                trailing: TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => _assign(
                                          data,
                                          preselectedDriverId: driver.id,
                                        ),
                                  child: Text(_t('Zmień', 'Change')),
                                ),
                              );
                            },
                          ),
                          if (index < data.drivers.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  _t('Lista pojazdów', 'Vehicle overview'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < data.vehicles.length;
                        index++
                      ) ...[
                        ListTile(
                          leading: const Icon(Icons.local_shipping_outlined),
                          title: Text(data.vehicles[index].registration),
                          subtitle: Text(
                            data.vehicles[index].currentDriverName ??
                                _t('Wolny', 'Available'),
                          ),
                          trailing: Text(
                            prettifyEnum(data.vehicles[index].status),
                          ),
                        ),
                        if (index < data.vehicles.length - 1)
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

  Widget _stat(String label, String value, IconData icon) => SizedBox(
    width: 146,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 7),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 3),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    ),
  );
}

class _ManagerData {
  const _ManagerData({
    required this.vehicles,
    required this.drivers,
    required this.issues,
    required this.repairs,
    required this.pendingRequests,
  });

  final List<Vehicle> vehicles;
  final List<Driver> drivers;
  final List<FleetIssue> issues;
  final List<Repair> repairs;
  final int pendingRequests;
}
