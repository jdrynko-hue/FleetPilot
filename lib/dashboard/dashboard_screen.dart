import 'package:flutter/material.dart';

import '../core/localization.dart';
import '../core/constants.dart';

import '../core/formatters.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import '../vehicles/vehicle_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.company,
    required this.refreshToken,
    super.key,
  });

  final CompanyMembership company;
  final int refreshToken;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _repository = FleetRepository();

  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.company.companyId != widget.company.companyId) {
      _load();
    }
  }

  void _load() {
    _future = _fetch();
  }

  Future<void> _openVehicle(String vehicleId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VehicleDetailScreen(
          company: widget.company,
          vehicleId: vehicleId,
          canManage: canManageForRole(widget.company.role),
        ),
      ),
    );

    if (changed == true && mounted) {
      setState(_load);
    }
  }

  Future<_DashboardData> _fetch() async {
    final results = await Future.wait([
      _repository.fetchVehicles(widget.company.companyId),
      _repository.fetchIssues(widget.company.companyId),
      _repository.fetchRepairs(widget.company.companyId),
    ]);

    return _DashboardData(
      vehicles: results[0] as List<Vehicle>,
      issues: results[1] as List<FleetIssue>,
      repairs: results[2] as List<Repair>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  SizedBox(height: 12),
                  Text(snapshot.error.toString(), textAlign: TextAlign.center),
                  SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => setState(_load),
                    icon: const Icon(Icons.refresh),
                    label: Text(tr('try_again')),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data!;

        final activeIssues = data.issues
            .where(
              (issue) => issue.status != 'closed' && issue.status != 'resolved',
            )
            .toList();

        final unavailable = data.vehicles
            .where(
              (vehicle) =>
                  vehicle.status == 'workshop' ||
                  vehicle.status == 'maintenance' ||
                  vehicle.status == 'off_road',
            )
            .length;

        final operational = data.vehicles
            .where(
              (vehicle) =>
                  vehicle.status == 'available' || vehicle.status == 'in_use',
            )
            .length;

        final now = DateTime.now();

        final monthStart = DateTime(now.year, now.month, 1);

        final monthSpend = data.repairs
            .where((repair) {
              final date = repair.completedAt ?? repair.bookedAt;

              return date != null && !date.isBefore(monthStart);
            })
            .fold<double>(0, (sum, repair) => sum + repair.totalCost);

        final attention = <_AttentionItem>[];

        final today = DateTime(now.year, now.month, now.day);

        int daysUntil(DateTime date) {
          final target = DateTime(date.year, date.month, date.day);
          return target.difference(today).inDays;
        }

        String reminderBand(int days) {
          if (days < 0) return '!';
          if (days <= 7) return '≤7d';
          if (days <= 14) return '≤14d';
          return '≤30d';
        }

        void addDateReminder({
          required Vehicle vehicle,
          required String label,
          required DateTime? date,
          required IconData icon,
        }) {
          if (date == null) return;

          final days = daysUntil(date);

          if (days <= 30) {
            attention.add(
              _AttentionItem(
                vehicleId: vehicle.id,
                icon: icon,
                title: '${vehicle.registration} — $label',
                subtitle:
                    '${reminderBand(days)} • ${tr('due_date')}: ${formatDate(date)}',
                sortOrder: days,
              ),
            );
          }
        }

        for (final vehicle in data.vehicles) {
          addDateReminder(
            vehicle: vehicle,
            label: vehicle.inspectionType,
            date: vehicle.inspectionDueDate,
            icon: Icons.fact_check_outlined,
          );

          addDateReminder(
            vehicle: vehicle,
            label: tr('service'),
            date: vehicle.serviceDueDate,
            icon: Icons.build_outlined,
          );

          addDateReminder(
            vehicle: vehicle,
            label: tr('insurance'),
            date: vehicle.insuranceExpiryDate,
            icon: Icons.shield_outlined,
          );

          final serviceMileage = vehicle.serviceDueMileage;

          if (serviceMileage != null) {
            final remaining = serviceMileage - vehicle.mileage;

            if (remaining <= 1500) {
              attention.add(
                _AttentionItem(
                  vehicleId: vehicle.id,
                  icon: Icons.speed_outlined,
                  title: '${vehicle.registration} — ${tr('service_mileage')}',
                  subtitle: remaining <= 0
                      ? '${tr('overdue')} • ${formatMileage(serviceMileage)} mi'
                      : '${formatMileage(remaining)} ${tr('miles_remaining')}',
                  sortOrder: remaining <= 0
                      ? -8000
                      : remaining <= 500
                      ? 5
                      : remaining <= 1000
                      ? 12
                      : 20,
                ),
              );
            }
          }
        }

        for (final issue in activeIssues) {
          if (issue.priority == 'high' || issue.priority == 'critical') {
            attention.add(
              _AttentionItem(
                vehicleId: issue.vehicleId,
                icon: Icons.warning_amber_rounded,
                title:
                    '${issue.registration ?? tr('vehicle')} — ${issue.title}',
                subtitle: issue.priority == 'critical'
                    ? tr('critical_priority')
                    : tr('high_priority'),
                sortOrder: issue.priority == 'critical' ? -10000 : -9000,
              ),
            );
          }
        }

        attention.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

        return RefreshIndicator(
          onRefresh: () async {
            setState(_load);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF102A43),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.company.companyName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            tr('fleet_status'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            data.vehicles.isEmpty
                                ? tr('add_first_vehicle')
                                : trf('fleet_operational', {
                                    'operational': operational,
                                    'total': data.vehicles.length,
                                  }),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 16),
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.local_shipping_rounded,
                        color: Colors.white,
                        size: 31,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 18),

              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = (constraints.maxWidth - 12) / 2;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricCard(
                        width: cardWidth,
                        icon: Icons.local_shipping_rounded,
                        value: data.vehicles.length.toString(),
                        label: tr('vehicles'),
                      ),
                      _MetricCard(
                        width: cardWidth,
                        icon: Icons.car_repair,
                        value: unavailable.toString(),
                        label: tr('unavailable'),
                      ),
                      _MetricCard(
                        width: cardWidth,
                        icon: Icons.warning_amber_rounded,
                        value: activeIssues.length.toString(),
                        label: tr('issues'),
                      ),
                      _MetricCard(
                        width: cardWidth,
                        icon: Icons.payments_outlined,
                        value: formatMoney(
                          monthSpend,
                          currency: widget.company.currency,
                        ),
                        label: tr('repairs_month'),
                        smallValue: true,
                      ),
                    ],
                  );
                },
              ),

              SizedBox(height: 26),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('requires_attention'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (attention.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDE8E8),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        attention.length.toString(),
                        style: const TextStyle(
                          color: Color(0xFFB42318),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),

              SizedBox(height: 10),

              if (attention.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9F8EF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.check_circle_outline,
                            color: Color(0xFF16803C),
                          ),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('all_under_control'),
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              SizedBox(height: 4),
                              Text(tr('no_urgent_items')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < attention.length && i < 6; i++) ...[
                        ListTile(
                          onTap: () => _openVehicle(attention[i].vehicleId),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 5,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFFDE8E8),
                            child: Icon(
                              attention[i].icon,
                              color: const Color(0xFFB42318),
                            ),
                          ),
                          title: Text(
                            attention[i].title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(attention[i].subtitle),
                        ),
                        if (i < attention.length - 1 && i < 5)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
    this.smallValue = false,
  });

  final double width;
  final IconData icon;
  final String value;
  final String label;
  final bool smallValue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              SizedBox(height: 14),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: smallValue ? 20 : 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardData {
  _DashboardData({
    required this.vehicles,
    required this.issues,
    required this.repairs,
  });

  final List<Vehicle> vehicles;
  final List<FleetIssue> issues;
  final List<Repair> repairs;
}

class _AttentionItem {
  _AttentionItem({
    required this.vehicleId,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.sortOrder,
  });

  final String vehicleId;
  final IconData icon;
  final String title;
  final String subtitle;
  final int sortOrder;
}
