import 'package:flutter/material.dart';

import 'garage_ui_text.dart';
import 'work_order_domain.dart';

/// Sanitised assignment projection supplied by an authorized Garage backend.
///
/// This widget never fetches jobs itself or evaluates user permissions.
/// Garage RLS/server APIs must return ONLY the signed-in mechanic's assigned
/// jobs. Never pass customer contact data or unshared Fleet records here.
class GarageMechanicAssignment {
  const GarageMechanicAssignment({
    required this.id,
    required this.registration,
    required this.make,
    required this.model,
    required this.complaint,
    required this.status,
  });

  final String id;
  final String registration;
  final String make;
  final String model;
  final String complaint;
  final GarageOrderStatus status;
}

/// Isolated mobile-friendly Garage view component.
///
/// Not yet mounted in the live Fleet shell: a production Garage authentication
/// and permission-filtered data layer must be available before that happens.
class GarageMechanicBoard extends StatelessWidget {
  const GarageMechanicBoard({
    required this.assignments,
    required this.onOpenAssignment,
    super.key,
  });

  final List<GarageMechanicAssignment> assignments;
  final ValueChanged<String> onOpenAssignment;

  String _statusName(GarageOrderStatus status) {
    switch (status) {
      case GarageOrderStatus.received:
        return GarageUiText.get('received');
      case GarageOrderStatus.diagnosing:
        return GarageUiText.get('diagnosing');
      case GarageOrderStatus.awaitingApproval:
        return GarageUiText.get('awaitingApproval');
      case GarageOrderStatus.awaitingParts:
        return GarageUiText.get('awaitingParts');
      case GarageOrderStatus.inProgress:
        return GarageUiText.get('inProgress');
      case GarageOrderStatus.ready:
        return GarageUiText.get('readyCollection');
      case GarageOrderStatus.collected:
        return GarageUiText.get('collected');
      case GarageOrderStatus.cancelled:
        return GarageUiText.get('cancelled');
    }
  }

  @override
  Widget build(BuildContext context) {
    final inProgress = assignments
        .where((job) => job.status == GarageOrderStatus.inProgress)
        .length;
    final awaitingParts = assignments
        .where((job) => job.status == GarageOrderStatus.awaitingParts)
        .length;
    final typography = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              GarageUiText.get('myAssignedJobs'),
              style: typography.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              GarageUiText.get('mechanicAssignedOnly'),
              style: typography.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  label: Text(
                    GarageUiText.format('mechanicTotal',
                        {'count': assignments.length}),
                  ),
                ),
                Chip(
                  label: Text(
                    GarageUiText.format('mechanicInProgress',
                        {'count': inProgress}),
                  ),
                ),
                Chip(
                  label: Text(
                    GarageUiText.format('mechanicAwaitingParts',
                        {'count': awaitingParts}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: assignments.isEmpty
                  ? Center(
                      child: Text(
                        GarageUiText.get('mechanicNoJobs'),
                        key: const Key('garage_mechanic_empty'),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      key: const Key('garage_mechanic_jobs'),
                      itemCount: assignments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final job = assignments[index];
                        return Card(
                          child: ListTile(
                            key: Key('garage_mechanic_job_${job.id}'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            title: Text(
                              job.registration.trim().isEmpty
                                  ? '${job.make} ${job.model}'
                                  : job.registration,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${job.make} ${job.model}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  job.complaint,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _statusName(job.status),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => onOpenAssignment(job.id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
