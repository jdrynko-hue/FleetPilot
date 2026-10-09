import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/localization.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    required this.company,
    required this.refreshToken,
    super.key,
  });

  final CompanyMembership company;
  final int refreshToken;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _repository = FleetRepository();
  late Future<_ReportsData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.company.companyId != widget.company.companyId) {
      _load();
    }
  }

  void _load() {
    _future = _fetch();
  }

  Future<_ReportsData> _fetch() async {
    final results = await Future.wait([
      _repository.fetchVehicles(widget.company.companyId),
      _repository.fetchIssues(widget.company.companyId),
      _repository.fetchRepairs(widget.company.companyId),
    ]);

    return _ReportsData(
      vehicles: results[0] as List<Vehicle>,
      issues: results[1] as List<FleetIssue>,
      repairs: results[2] as List<Repair>,
    );
  }

  DateTime? _repairDate(Repair repair) {
    return repair.completedAt ?? repair.startedAt ?? repair.bookedAt;
  }

  double _costSince(List<Repair> repairs, int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));

    return repairs
        .where((repair) {
          final date = _repairDate(repair);
          return date != null && !date.isBefore(cutoff);
        })
        .fold<double>(0, (sum, repair) => sum + repair.totalCost);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReportsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(snapshot.error.toString()),
            ),
          );
        }

        final data = snapshot.data!;

        final cost30 = _costSince(data.repairs, 30);
        final cost90 = _costSince(data.repairs, 90);
        final cost365 = _costSince(data.repairs, 365);

        final activeIssues = data.issues
            .where(
              (issue) => issue.status != 'resolved' && issue.status != 'closed',
            )
            .length;

        final cutoff365 = DateTime.now().subtract(const Duration(days: 365));

        final costByVehicle = <String, double>{};
        final registrationByVehicle = <String, String>{};

        for (final repair in data.repairs) {
          final date = _repairDate(repair);

          if (date == null || date.isBefore(cutoff365)) {
            continue;
          }

          costByVehicle.update(
            repair.vehicleId,
            (value) => value + repair.totalCost,
            ifAbsent: () => repair.totalCost,
          );

          registrationByVehicle[repair.vehicleId] =
              repair.registration ?? tr('vehicle');
        }

        final ranking = costByVehicle.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return RefreshIndicator(
          onRefresh: () async {
            setState(_load);
            await _future;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
            children: [
              Text(
                tr('fleet_reports'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(tr('costs_and_performance')),
              const SizedBox(height: 20),

              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final cardWidth = width >= 900
                      ? (width - 36) / 4
                      : width >= 600
                      ? (width - 12) / 2
                      : width;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _ReportMetric(
                        width: cardWidth,
                        icon: Icons.calendar_view_month_outlined,
                        label: tr('last_30_days'),
                        value: formatMoney(
                          cost30,
                          currency: widget.company.currency,
                        ),
                      ),
                      _ReportMetric(
                        width: cardWidth,
                        icon: Icons.date_range_outlined,
                        label: tr('last_90_days'),
                        value: formatMoney(
                          cost90,
                          currency: widget.company.currency,
                        ),
                      ),
                      _ReportMetric(
                        width: cardWidth,
                        icon: Icons.calendar_today_outlined,
                        label: tr('last_365_days'),
                        value: formatMoney(
                          cost365,
                          currency: widget.company.currency,
                        ),
                      ),
                      _ReportMetric(
                        width: cardWidth,
                        icon: Icons.warning_amber_rounded,
                        label: tr('active_issues'),
                        value: activeIssues.toString(),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 28),

              Row(
                children: [
                  const Icon(Icons.payments_outlined),
                  const SizedBox(width: 8),
                  Text(
                    tr('most_expensive_vehicles'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Card(
                child: ranking.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(22),
                        child: Text(tr('no_cost_data')),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < ranking.length && i < 8; i++) ...[
                            ListTile(
                              leading: CircleAvatar(child: Text('${i + 1}')),
                              title: Text(
                                registrationByVehicle[ranking[i].key] ??
                                    tr('vehicle'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(tr('last_365_days')),
                              trailing: Text(
                                formatMoney(
                                  ranking[i].value,
                                  currency: widget.company.currency,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (i != ranking.length - 1 && i != 7)
                              const Divider(height: 1),
                          ],
                        ],
                      ),
              ),

              const SizedBox(height: 28),

              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth >= 600
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _ReportMetric(
                        width: cardWidth,
                        icon: Icons.local_shipping_outlined,
                        label: tr('vehicles'),
                        value: data.vehicles.length.toString(),
                      ),
                      _ReportMetric(
                        width: cardWidth,
                        icon: Icons.build_circle_outlined,
                        label: tr('total_repairs'),
                        value: data.repairs.length.toString(),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 14),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportsData {
  const _ReportsData({
    required this.vehicles,
    required this.issues,
    required this.repairs,
  });

  final List<Vehicle> vehicles;
  final List<FleetIssue> issues;
  final List<Repair> repairs;
}
