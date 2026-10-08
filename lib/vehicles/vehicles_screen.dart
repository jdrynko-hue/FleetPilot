import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/widgets.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import 'vehicle_detail_screen.dart';
import 'vehicle_form_screen.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({
    required this.company,
    required this.canManage,
    required this.refreshToken,
    required this.onDataChanged,
    super.key,
  });

  final CompanyMembership company;
  final bool canManage;
  final int refreshToken;
  final VoidCallback onDataChanged;

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final _repository = FleetRepository();
  final _search = TextEditingController();
  late Future<List<Vehicle>> _future;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant VehiclesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.company.companyId != widget.company.companyId) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    _future = _repository.fetchVehicles(widget.company.companyId);
  }

  Future<void> _openForm({Vehicle? vehicle}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VehicleFormScreen(
          company: widget.company,
          vehicle: vehicle,
        ),
      ),
    );
    if (changed == true) {
      setState(_load);
      widget.onDataChanged();
    }
  }

  Future<void> _openDetail(Vehicle vehicle) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VehicleDetailScreen(
          company: widget.company,
          vehicleId: vehicle.id,
          canManage: widget.canManage,
        ),
      ),
    );
    if (changed == true) {
      setState(_load);
      widget.onDataChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Vehicle>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorState(error: snapshot.error!, onRetry: () => setState(_load));
        }

        final query = _search.text.trim().toLowerCase();
        final all = snapshot.data ?? [];
        final vehicles = all.where((v) {
          final matchesSearch = query.isEmpty ||
              v.registration.toLowerCase().contains(query) ||
              (v.make ?? '').toLowerCase().contains(query) ||
              (v.model ?? '').toLowerCase().contains(query) ||
              (v.currentDriverName ?? '').toLowerCase().contains(query);
          final matchesStatus = _statusFilter == null || v.status == _statusFilter;
          return matchesSearch && matchesStatus;
        }).toList();

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: widget.canManage
              ? FloatingActionButton.extended(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add vehicle'),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: () async => setState(_load),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text('Vehicles', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 360,
                      child: TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          labelText: 'Search vehicles',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        initialValue: _statusFilter,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All statuses')),
                          ...vehicleStatuses.map(
                            (s) => DropdownMenuItem<String?>(value: s, child: Text(prettifyEnum(s))),
                          ),
                        ],
                        onChanged: (value) => setState(() => _statusFilter = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (vehicles.isEmpty)
                  const SizedBox(
                    height: 360,
                    child: EmptyState(
                      icon: Icons.local_shipping_outlined,
                      title: 'No vehicles yet',
                      message: 'Add the first vehicle when you are ready to start testing the fleet workspace.',
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < vehicles.length; i++) ...[
                          ListTile(
                            onTap: () => _openDetail(vehicles[i]),
                            leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
                            title: Text(vehicles[i].registration),
                            subtitle: Text(
                              [
                                '${vehicles[i].make ?? ''} ${vehicles[i].model ?? ''}'.trim(),
                                if (vehicles[i].currentDriverName != null) vehicles[i].currentDriverName!,
                                '${formatMileage(vehicles[i].mileage)} mi',
                              ].where((e) => e.isNotEmpty).join(' • '),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StatusPill(label: prettifyEnum(vehicles[i].status)),
                                if (widget.canManage) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: 'Edit',
                                    onPressed: () => _openForm(vehicle: vehicles[i]),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (i != vehicles.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 84),
              ],
            ),
          ),
        );
      },
    );
  }
}
