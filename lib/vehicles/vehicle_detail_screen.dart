import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/localization.dart';
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
      _repository.fetchVehicleAssignments(
        widget.company.companyId,
        widget.vehicleId,
      ),
    ]);

    return _VehicleDetailData(
      vehicle: results[0] as Vehicle,
      issues: results[1] as List<FleetIssue>,
      repairs: results[2] as List<Repair>,
      assignments: results[3] as List<VehicleAssignment>,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    _changed = true;
  }

  bool _isDateUrgent(DateTime? date) {
    if (date == null) return false;
    return date.difference(DateTime.now()).inDays <= 30;
  }

  bool _isMileageUrgent(Vehicle vehicle) {
    final due = vehicle.serviceDueMileage;
    if (due == null) return false;
    return due - vehicle.mileage <= 1500;
  }

  bool _issueIsActive(FleetIssue issue) {
    return issue.status != 'resolved' && issue.status != 'closed';
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
        final vehicle = data.vehicle;

        final activeIssues = data.issues.where(_issueIsActive).toList();

        final totalRepairCost = data.repairs.fold<double>(
          0,
          (sum, repair) => sum + repair.totalCost,
        );

        final timeline = <_TimelineEvent>[
          for (final assignment in data.assignments)
            _TimelineEvent(
              date: assignment.startsAt,
              icon: Icons.person_outline,
              title: '${tr('driver')}: ${assignment.driverName}',
              subtitle: assignment.endsAt == null
                  ? tr('active')
                  : '${formatDateTime(assignment.startsAt)} — ${formatDateTime(assignment.endsAt!)}',
            ),
          for (final issue in data.issues)
            _TimelineEvent(
              date: issue.reportedAt,
              icon: Icons.warning_amber_outlined,
              title: '${tr('issues')}: ${issue.title}',
              subtitle: '${tr(issue.priority)} • ${tr(issue.status)}',
            ),
          for (final repair in data.repairs)
            if ((repair.completedAt ?? repair.startedAt ?? repair.bookedAt) !=
                null)
              _TimelineEvent(
                date:
                    repair.completedAt ?? repair.startedAt ?? repair.bookedAt!,
                icon: Icons.build_circle_outlined,
                title: repair.description ?? tr('repair'),
                subtitle:
                    '${tr(repair.status)} • ${formatMoney(repair.totalCost, currency: widget.company.currency)}',
              ),
        ]..sort((a, b) => b.date.compareTo(a.date));

        return Scaffold(
          appBar: AppBar(
            leading: BackButton(
              onPressed: () => Navigator.pop(context, _changed),
            ),
            title: Text(vehicle.registration),
            actions: [
              if (widget.canManage)
                IconButton(
                  tooltip: tr('edit_vehicle'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VehicleFormScreen(
                          company: widget.company,
                          vehicle: vehicle,
                        ),
                      ),
                    );

                    if (changed == true) {
                      await _refresh();
                    }
                  },
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                _VehicleHero(vehicle: vehicle),
                const SizedBox(height: 16),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final cardWidth = width >= 720
                        ? (width - 24) / 3
                        : (width - 12) / 2;

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _MetricCard(
                            icon: Icons.speed_outlined,
                            label: tr('mileage'),
                            value: '${formatMileage(vehicle.mileage)} mi',
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _MetricCard(
                            icon: Icons.person_outline,
                            label: tr('driver'),
                            value:
                                vehicle.currentDriverName ?? tr('unassigned'),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _MetricCard(
                            icon: Icons.warning_amber_rounded,
                            label: tr('issues'),
                            value: activeIssues.length.toString(),
                            urgent: activeIssues.any(
                              (issue) =>
                                  issue.priority == 'critical' ||
                                  issue.priority == 'high',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _MetricCard(
                            icon: Icons.payments_outlined,
                            label: tr('repairs'),
                            value: formatMoney(
                              totalRepairCost,
                              currency: widget.company.currency,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                _SectionTitle(
                  icon: Icons.event_available_outlined,
                  title: vehicle.inspectionType,
                ),
                const SizedBox(height: 10),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final cardWidth = width >= 720 ? (width - 24) / 3 : width;

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _DueCard(
                            icon: Icons.fact_check_outlined,
                            label: vehicle.inspectionType,
                            value: formatDate(vehicle.inspectionDueDate),
                            urgent: _isDateUrgent(vehicle.inspectionDueDate),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _DueCard(
                            icon: Icons.build_outlined,
                            label: tr('service'),
                            value: vehicle.serviceDueMileage != null
                                ? '${formatMileage(vehicle.serviceDueMileage)} mi'
                                : formatDate(vehicle.serviceDueDate),
                            urgent:
                                _isMileageUrgent(vehicle) ||
                                _isDateUrgent(vehicle.serviceDueDate),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: _DueCard(
                            icon: Icons.shield_outlined,
                            label: tr('insurance'),
                            value: formatDate(vehicle.insuranceExpiryDate),
                            urgent: _isDateUrgent(vehicle.insuranceExpiryDate),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 28),

                _SectionHeader(
                  title: tr('issues'),
                  count: activeIssues.length,
                  canAdd: widget.canManage,
                  onAdd: () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => IssueFormScreen(
                          company: widget.company,
                          initialVehicleId: vehicle.id,
                        ),
                      ),
                    );

                    if (changed == true) {
                      await _refresh();
                    }
                  },
                ),

                const SizedBox(height: 8),

                Card(
                  clipBehavior: Clip.antiAlias,
                  child: activeIssues.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(tr('no_issues_recorded'))),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < activeIssues.length; i++) ...[
                              _IssueTile(issue: activeIssues[i]),
                              if (i != activeIssues.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
                ),

                const SizedBox(height: 28),

                _SectionHeader(
                  title: tr('repairs'),
                  count: data.repairs.length,
                  canAdd: widget.canManage,
                  onAdd: () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RepairFormScreen(
                          company: widget.company,
                          initialVehicleId: vehicle.id,
                        ),
                      ),
                    );

                    if (changed == true) {
                      await _refresh();
                    }
                  },
                ),

                const SizedBox(height: 8),

                Card(
                  clipBehavior: Clip.antiAlias,
                  child: data.repairs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(tr('no_repairs_recorded')),
                        )
                      : Column(
                          children: [
                            for (
                              var i = 0;
                              i < data.repairs.length && i < 5;
                              i++
                            ) ...[
                              _RepairTile(
                                repair: data.repairs[i],
                                currency: widget.company.currency,
                              ),
                              if (i != data.repairs.length - 1 && i != 4)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
                ),

                if (timeline.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _SectionTitle(
                    icon: Icons.history_rounded,
                    title: tr('history'),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < timeline.length; i++) ...[
                          _TimelineTile(event: timeline[i]),
                          if (i != timeline.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                ],

                if ((vehicle.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _SectionTitle(icon: Icons.notes_outlined, title: tr('notes')),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(vehicle.notes!),
                    ),
                  ),
                ],

                if ((vehicle.vin ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'VIN: ${vehicle.vin}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VehicleHero extends StatelessWidget {
  const _VehicleHero({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modelText =
        '${vehicle.make ?? ''} ${vehicle.model ?? ''} ${vehicle.year ?? ''}'
            .trim();

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.registration,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (modelText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(modelText, style: theme.textTheme.titleMedium),
                      ],
                    ],
                  ),
                ),
                _VehicleStatus(status: vehicle.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleStatus extends StatelessWidget {
  const _VehicleStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unavailable = const {
      'workshop',
      'maintenance',
      'off_road',
    }.contains(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: unavailable ? scheme.errorContainer : scheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tr(status),
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.urgent = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: urgent ? scheme.errorContainer : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.urgent,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: urgent ? scheme.errorContainer : scheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: urgent ? scheme.error : scheme.primaryContainer,
              foregroundColor: urgent
                  ? scheme.onError
                  : scheme.onPrimaryContainer,
              child: Icon(icon, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 21),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.canAdd,
    required this.onAdd,
  });

  final String title;
  final int count;
  final bool canAdd;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(count.toString()),
              ),
            ],
          ),
        ),
        if (canAdd)
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(tr('add')),
          ),
      ],
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue});

  final FleetIssue issue;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(
        issue.priority == 'critical' || issue.priority == 'high'
            ? Icons.error_outline
            : Icons.warning_amber_outlined,
      ),
      title: Text(
        issue.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${tr(issue.priority)} • ${formatDateTime(issue.reportedAt)}',
      ),
      trailing: StatusPill(label: tr(issue.status)),
    );
  }
}

class _RepairTile extends StatelessWidget {
  const _RepairTile({required this.repair, required this.currency});

  final Repair repair;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: const Icon(Icons.build_circle_outlined),
      title: Text(
        repair.description ?? tr('repair'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${repair.garageName ?? tr('not_assigned')} • ${tr(repair.status)}',
      ),
      trailing: Text(
        formatMoney(repair.totalCost, currency: currency),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.event});

  final _TimelineEvent event;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        child: Icon(event.icon, size: 20),
      ),
      title: Text(
        event.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('${formatDateTime(event.date)}\n${event.subtitle}'),
      isThreeLine: true,
    );
  }
}

class _TimelineEvent {
  const _TimelineEvent({
    required this.date,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final DateTime date;
  final IconData icon;
  final String title;
  final String subtitle;
}

class _VehicleDetailData {
  _VehicleDetailData({
    required this.vehicle,
    required this.issues,
    required this.repairs,
    required this.assignments,
  });

  final Vehicle vehicle;
  final List<FleetIssue> issues;
  final List<Repair> repairs;
  final List<VehicleAssignment> assignments;
}
