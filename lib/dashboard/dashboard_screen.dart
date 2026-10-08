import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/widgets.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';

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
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorState(error: snapshot.error!, onRetry: () => setState(_load));
        }

        final data = snapshot.data!;
        final now = DateTime.now();
        final inThirtyDays = now.add(const Duration(days: 30));
        final activeIssues = data.issues.where((i) => i.status != 'closed' && i.status != 'resolved').toList();
        final today = DateTime(now.year, now.month, now.day);
        final dueSoon = data.vehicles.where((v) {
          final due = v.inspectionDueDate;
          return due != null && due.isBefore(inThirtyDays.add(const Duration(days: 1)));
        }).toList();
        final unavailable = data.vehicles.where((v) => ['workshop', 'maintenance', 'off_road'].contains(v.status)).length;
        final monthStart = DateTime(now.year, now.month, 1);
        final monthSpend = data.repairs.where((r) {
          final date = r.completedAt ?? r.bookedAt;
          return date != null && date.isAfter(monthStart.subtract(const Duration(seconds: 1)));
        }).fold<double>(0, (sum, r) => sum + r.totalCost);

        final attention = <_AttentionItem>[
          ...dueSoon.map((v) => _AttentionItem(
                icon: Icons.event_busy_outlined,
                title: v.inspectionDueDate!.isBefore(today)
                    ? '${v.registration} — ${v.inspectionType} OVERDUE (${formatDate(v.inspectionDueDate)})'
                    : '${v.registration} — ${v.inspectionType} due ${formatDate(v.inspectionDueDate)}',
                subtitle: '${v.make ?? ''} ${v.model ?? ''}'.trim(),
              )),
          ...activeIssues
              .where((i) => i.priority == 'critical' || i.priority == 'high')
              .map((i) => _AttentionItem(
                    icon: Icons.report_problem_outlined,
                    title: '${i.registration ?? 'Vehicle'} — ${i.title}',
                    subtitle: '${prettifyEnum(i.priority)} priority • ${prettifyEnum(i.status)}',
                  )),
          ...data.vehicles
              .where((v) => v.status == 'off_road' || v.status == 'workshop')
              .map((v) => _AttentionItem(
                    icon: Icons.car_repair_outlined,
                    title: '${v.registration} — ${prettifyEnum(v.status)}',
                    subtitle: v.currentDriverName ?? 'No driver assigned',
                  )),
        ];

        return RefreshIndicator(
          onRefresh: () async => setState(_load),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('Dashboard', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(widget.company.companyName),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1000 ? 4 : constraints.maxWidth >= 600 ? 2 : 1;
                  const gap = 12.0;
                  final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                  final cards = [
                    MetricCard(label: 'Vehicles', value: data.vehicles.length.toString(), icon: Icons.local_shipping_outlined),
                    MetricCard(label: 'Unavailable', value: unavailable.toString(), icon: Icons.car_repair_outlined),
                    MetricCard(label: 'Open issues', value: activeIssues.length.toString(), icon: Icons.report_problem_outlined),
                    MetricCard(label: 'Repair spend this month', value: formatMoney(monthSpend, currency: widget.company.currency), icon: Icons.payments_outlined),
                  ];
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: cards.map((card) => SizedBox(width: width, child: card)).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text('Needs attention', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (attention.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Nothing urgent right now.'),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < attention.length; i++) ...[
                        ListTile(
                          leading: Icon(attention[i].icon),
                          title: Text(attention[i].title),
                          subtitle: attention[i].subtitle.isEmpty ? null : Text(attention[i].subtitle),
                        ),
                        if (i != attention.length - 1) const Divider(height: 1),
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

class _DashboardData {
  _DashboardData({required this.vehicles, required this.issues, required this.repairs});

  final List<Vehicle> vehicles;
  final List<FleetIssue> issues;
  final List<Repair> repairs;
}

class _AttentionItem {
  _AttentionItem({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;
}
