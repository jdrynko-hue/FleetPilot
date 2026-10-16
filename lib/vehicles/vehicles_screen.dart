import 'package:flutter/material.dart';

import '../core/localization.dart';

import '../core/constants.dart';
import '../core/widgets.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import 'vehicle_detail_screen.dart';
import 'vehicle_form_screen.dart';
import '../notifications/notifications_screen.dart';
import 'insurance_expiry.dart';
import 'vehicle_list_tile.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({
    required this.company,
    required this.canManage,
    required this.refreshToken,
    required this.onDataChanged,
    this.repository,
    super.key,
  });

  final CompanyMembership company;
  final bool canManage;
  final int refreshToken;
  final VoidCallback onDataChanged;
  final FleetRepository? repository;

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  late final _repository = widget.repository ?? FleetRepository();
  final _search = TextEditingController();
  late Future<List<Vehicle>> _future;
  String? _statusFilter;
  bool _insuranceOnly = false;

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
        builder: (_) =>
            VehicleFormScreen(company: widget.company, vehicle: vehicle),
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
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorState(
            error: snapshot.error!,
            onRetry: () => setState(_load),
          );
        }

        final query = _search.text.trim().toLowerCase();
        final all = snapshot.data ?? [];
        final today = DateTime.now();
        final insuranceAttention = all.where(
          (v) => insuranceNeedsAttention(v.insuranceExpiryDate, today),
        ).length;
        final vehicles = all.where((v) {
          final matchesSearch =
              query.isEmpty ||
              v.registration.toLowerCase().contains(query) ||
              (v.make ?? '').toLowerCase().contains(query) ||
              (v.model ?? '').toLowerCase().contains(query) ||
              (v.currentDriverName ?? '').toLowerCase().contains(query);
          final matchesStatus =
              _statusFilter == null || v.status == _statusFilter;
          return matchesSearch &&
              matchesStatus &&
              (!_insuranceOnly ||
                  insuranceNeedsAttention(v.insuranceExpiryDate, today));
        }).toList();

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: widget.canManage
              ? FloatingActionButton.extended(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add),
                  label: Text(tr('add_vehicle')),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: () async => setState(_load),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  tr('vehicles'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          labelText: tr('search_vehicles'),
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: _statusFilter,
                        decoration: InputDecoration(labelText: tr('status')),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(tr('all_statuses')),
                          ),
                          ...vehicleStatuses.map(
                            (s) => DropdownMenuItem<String?>(
                              value: s,
                              child: Text(prettifyEnum(s)),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _statusFilter = value),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('${tr('insurance_due_filter')} ($insuranceAttention)'),
                        value: _insuranceOnly,
                        onChanged: (value) => setState(() => _insuranceOnly = value ?? false),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => NotificationsScreen(company: widget.company),
                        ),
                      ),
                      icon: const Icon(Icons.notifications_outlined),
                      label: Text(tr('notification_preferences')),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (vehicles.isEmpty)
                  SizedBox(
                    height: 360,
                    child: EmptyState(
                      icon: Icons.local_shipping_outlined,
                      title: tr(all.isEmpty ? 'no_vehicles_yet' : 'insurance_no_matches'),
                      message: tr(all.isEmpty ? 'no_vehicles_message' : 'insurance_change_filters'),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < vehicles.length; i++) ...[
                          VehicleListTile(
                            vehicle: vehicles[i],
                            onOpen: () => _openDetail(vehicles[i]),
                            onEdit: widget.canManage
                                ? () => _openForm(vehicle: vehicles[i])
                                : null,
                          ),
                          if (i != vehicles.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                SizedBox(height: 84),
              ],
            ),
          ),
        );
      },
    );
  }
}
