import 'package:flutter/material.dart';

import '../core/localization.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/widgets.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import '../issues/issue_form_screen.dart';
import '../repairs/repair_form_screen.dart';
import 'vehicle_form_screen.dart';

class VehicleDetailScreen extends StatefulWidget {
  const VehicleDetailScreen({
    required this.company,
    required this.vehicleId,
    required this.canManage,
    super.key,
  });

  final CompanyMembership company;
  final String vehicleId;
  final bool canManage;

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  final _repository = FleetRepository();
  late Future<_VehicleDetailData> _future;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _fetch();
  }

  Future<_VehicleDetailData> _fetch() async {
    final results = await Future.wait([
      _repository.fetchVehicle(widget.company.companyId, widget.vehicleId),
      _repository.fetchIssues(
        widget.company.companyId,
        vehicleId: widget.vehicleId,
      ),
      _repository.fetchRepairs(
        widget.company.companyId,
        vehicleId: widget.vehicleId,
      ),
    ]);
    return _VehicleDetailData(
      vehicle: results[0] as Vehicle,
      issues: results[1] as List<FleetIssue>,
      repairs: results[2] as List<Repair>,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    _changed = true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_VehicleDetailData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: ErrorState(
              error: snapshot.error!,
              onRetry: () => setState(_load),
            ),
          );
        }
        final data = snapshot.data!;
        final v = data.vehicle;
        return Scaffold(
          appBar: AppBar(
            leading: BackButton(
              onPressed: () => Navigator.pop(context, _changed),
            ),
            title: Text(v.registration),
            actions: [
              if (widget.canManage)
                IconButton(
                  tooltip: tr('edit_vehicle'),
                  onPressed: () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VehicleFormScreen(
                          company: widget.company,
                          vehicle: v,
                        ),
                      ),
                    );
                    if (changed == true) await _refresh();
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _InfoCard(
                      label: tr('status'),
                      value: prettifyEnum(v.status),
                    ),
                    _InfoCard(
                      label: tr('driver'),
                      value: v.currentDriverName ?? tr('unassigned'),
                    ),
                    _InfoCard(
                      label: tr('mileage'),
                      value: '${formatMileage(v.mileage)} mi',
                    ),
                    _InfoCard(
                      label: v.inspectionType,
                      value: formatDate(v.inspectionDueDate),
                    ),
                    _InfoCard(
                      label: tr('service'),
                      value: v.serviceDueMileage != null
                          ? '${formatMileage(v.serviceDueMileage)} mi'
                          : formatDate(v.serviceDueDate),
                    ),
                    _InfoCard(
                      label: tr('insurance'),
                      value: formatDate(v.insuranceExpiryDate),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Text(
                  '${v.make ?? ''} ${v.model ?? ''} ${v.year ?? ''}'.trim(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if ((v.vin ?? '').isNotEmpty) Text('VIN: ${v.vin}'),
                if ((v.notes ?? '').isNotEmpty) ...[
                  SizedBox(height: 12),
                  Text(v.notes!),
                ],
                SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('issues'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (widget.canManage)
                      TextButton.icon(
                        onPressed: () async {
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IssueFormScreen(
                                company: widget.company,
                                initialVehicleId: v.id,
                              ),
                            ),
                          );
                          if (changed == true) await _refresh();
                        },
                        icon: const Icon(Icons.add),
                        label: Text(tr('add')),
                      ),
                  ],
                ),
                Card(
                  child: data.issues.isEmpty
                      ? Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(tr('no_issues_recorded')),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < data.issues.length; i++) ...[
                              ListTile(
                                title: Text(data.issues[i].title),
                                subtitle: Text(
                                  '${prettifyEnum(data.issues[i].priority)} • ${prettifyEnum(data.issues[i].status)} • ${formatDateTime(data.issues[i].reportedAt)}',
                                ),
                                trailing: StatusPill(
                                  label: prettifyEnum(data.issues[i].status),
                                ),
                              ),
                              if (i != data.issues.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
                ),
                SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('repairs'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (widget.canManage)
                      TextButton.icon(
                        onPressed: () async {
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RepairFormScreen(
                                company: widget.company,
                                initialVehicleId: v.id,
                              ),
                            ),
                          );
                          if (changed == true) await _refresh();
                        },
                        icon: const Icon(Icons.add),
                        label: Text(tr('add')),
                      ),
                  ],
                ),
                Card(
                  child: data.repairs.isEmpty
                      ? Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(tr('no_repairs_recorded')),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < data.repairs.length; i++) ...[
                              ListTile(
                                title: Text(
                                  data.repairs[i].description ?? tr('repair'),
                                ),
                                subtitle: Text(
                                  '${data.repairs[i].garageName ?? tr('not_assigned')} • ${prettifyEnum(data.repairs[i].status)}',
                                ),
                                trailing: Text(
                                  formatMoney(
                                    data.repairs[i].totalCost,
                                    currency: widget.company.currency,
                                  ),
                                ),
                              ),
                              if (i != data.repairs.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
                ),
                SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VehicleDetailData {
  _VehicleDetailData({
    required this.vehicle,
    required this.issues,
    required this.repairs,
  });
  final Vehicle vehicle;
  final List<FleetIssue> issues;
  final List<Repair> repairs;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
