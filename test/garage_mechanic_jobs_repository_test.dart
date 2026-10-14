import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/garage/mechanic_jobs_repository.dart';
import 'package:fleetpilot/garage/work_order_domain.dart';

void main() {
  test('maps a sanitized RPC row to the mechanic board projection', () {
    final rows = GarageMechanicJobsRepository.parseMyAssignments([
      {
        'id': '00000000-0000-4000-8000-000000000401',
        'registration': 'FJ70 VDF',
        'make': 'Mercedes-Benz',
        'model': 'Sprinter',
        'complaint': 'Inspect brake system',
        'status': 'diagnosing',
      },
      {
        'id': '00000000-0000-4000-8000-000000000402',
        'registration': null,
        'make': 'BMW',
        'model': '320',
        'complaint': 'Engine light',
        'status': 'awaiting_parts',
      },
    ]);
    expect(rows, hasLength(2));
    expect(rows[0].registration, 'FJ70 VDF');
    expect(rows[0].status, GarageOrderStatus.diagnosing);
    expect(rows[1].registration, isEmpty);
    expect(rows[1].status, GarageOrderStatus.awaitingParts);
    expect(() => rows.clear(), throwsUnsupportedError);
  });

  test('all supported status values match the server snake_case labels', () {
    final values = {
      'received': GarageOrderStatus.received,
      'diagnosing': GarageOrderStatus.diagnosing,
      'awaiting_approval': GarageOrderStatus.awaitingApproval,
      'awaiting_parts': GarageOrderStatus.awaitingParts,
      'in_progress': GarageOrderStatus.inProgress,
      'ready': GarageOrderStatus.ready,
      'collected': GarageOrderStatus.collected,
      'cancelled': GarageOrderStatus.cancelled,
    };
    for (final entry in values.entries) {
      final rows = GarageMechanicJobsRepository.parseMyAssignments([
        {
          'id': 'job',
          'registration': 'AB123',
          'make': 'Ford',
          'model': 'Focus',
          'complaint': 'Brake complaint',
          'status': entry.key,
        },
      ]);
      expect(rows.single.status, entry.value);
    }
  });

  test('empty response is a safe empty assignment list', () {
    final rows = GarageMechanicJobsRepository.parseMyAssignments([]);
    expect(rows, isEmpty);
    expect(() => rows.add(rows.first), throwsRangeError);
  });

  test('invalid RPC payload fails closed instead of displaying stale data', () {
    for (final payload in [null, 'not a list', {}, 3]) {
      expect(
        () => GarageMechanicJobsRepository.parseMyAssignments(payload),
        throwsFormatException,
      );
    }
  });

  test('unknown status cannot silently become a valid work status', () {
    expect(
      () => GarageMechanicJobsRepository.parseMyAssignments([
        {
          'id': 'job',
          'registration': null,
          'make': 'Ford',
          'model': 'Transit',
          'complaint': 'Brake failure',
          'status': 'approved_without_evidence',
        },
      ]),
      throwsFormatException,
    );
  });

  test('missing required fields and wrong types are rejected', () {
    final valid = <String, Object?>{
      'id': 'job',
      'registration': 'LM12 ABC',
      'make': 'Ford',
      'model': 'Transit',
      'complaint': 'Inspect braking',
      'status': 'received',
    };
    for (final field in ['id', 'make', 'model', 'complaint', 'status']) {
      final missing = {...valid}..remove(field);
      expect(
        () => GarageMechanicJobsRepository.parseMyAssignments([missing]),
        throwsFormatException,
      );
      final blank = {...valid, field: '   '};
      expect(
        () => GarageMechanicJobsRepository.parseMyAssignments([blank]),
        throwsFormatException,
      );
    }
    expect(
      () => GarageMechanicJobsRepository.parseMyAssignments([
        {...valid, 'registration': 123},
      ]),
      throwsFormatException,
    );
    expect(
      () => GarageMechanicJobsRepository.parseMyAssignments([
        {...valid, 'make': 999},
      ]),
      throwsFormatException,
    );
    expect(
      () => GarageMechanicJobsRepository.parseMyAssignments(['not a row']),
      throwsFormatException,
    );
  });

  test('response maps ONLY fields needed by mechanic UI', () {
    final rows = GarageMechanicJobsRepository.parseMyAssignments([
      {
        'id': 'job-1',
        'registration': 'FJ70 VDF',
        'make': 'Mercedes',
        'model': 'Sprinter',
        'complaint': 'Brake repair',
        'status': 'in_progress',
        // Misconfigured future RPCs should not be read into the widget.
        'customer_email': 'private@example.test',
        'customer_phone': '0123456789',
        'stripe_customer_id': 'cus_test',
      },
    ]);
    final job = rows.single;
    expect(job.id, 'job-1');
    expect(job.complaint, 'Brake repair');
    expect(job.status, GarageOrderStatus.inProgress);
    expect(job.toString(), isNot(contains('private@example.test')));
  });
}
