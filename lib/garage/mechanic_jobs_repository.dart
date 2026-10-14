import 'package:supabase_flutter/supabase_flutter.dart';

import 'mechanic_board.dart';
import 'work_order_domain.dart';

/// Read-only RPC adapter for the future Garage mechanic screen.
///
/// The SQL function garage_my_assigned_jobs is SECURITY INVOKER, checking
/// auth.uid(), workshop membership and row-level security. These client-side
/// validations are data quality checks, NOT a replacement for database RLS.
/// Not wired to production Fleet navigation until Garage schema is deployed.
class GarageMechanicJobsRepository {
  GarageMechanicJobsRepository(this.client);

  final SupabaseClient client;

  static final _workspaceId = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Future<List<GarageMechanicAssignment>> fetchMyAssignments(
    String workspaceId,
  ) async {
    if (!_workspaceId.hasMatch(workspaceId)) {
      throw ArgumentError.value(workspaceId, 'workspaceId', 'UUID required');
    }
    if (client.auth.currentUser == null) {
      throw StateError('Signed-in garage membership required');
    }
    final data = await client.rpc(
      'garage_my_assigned_jobs',
      params: {'p_workspace_id': workspaceId},
    );
    return parseMyAssignments(data);
  }

  /// Strict parsing rejects malformed records instead of substituting
  /// fabricated statuses, vehicle details or work-order identifiers.
  static List<GarageMechanicAssignment> parseMyAssignments(Object? data) {
    if (data is! List) {
      throw const FormatException('Expected assigned work-order rows');
    }
    final assignments = <GarageMechanicAssignment>[];
    for (final record in data) {
      if (record is! Map) {
        throw const FormatException('Invalid assigned work-order row');
      }
      final id = _required(record, 'id');
      final registration = _optional(record, 'registration');
      final make = _required(record, 'make');
      final model = _required(record, 'model');
      final complaint = _required(record, 'complaint');
      final status = _status(_required(record, 'status'));
      assignments.add(
        GarageMechanicAssignment(
          id: id,
          registration: registration,
          make: make,
          model: model,
          complaint: complaint,
          status: status,
        ),
      );
    }
    return List.unmodifiable(assignments);
  }

  static String _required(Map<dynamic, dynamic> row, String name) {
    final value = row[name];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid assigned job field: $name');
    }
    return value;
  }

  static String _optional(Map<dynamic, dynamic> row, String name) {
    final value = row[name];
    if (value == null) return '';
    if (value is! String) {
      throw FormatException('Invalid optional assigned job field: $name');
    }
    return value;
  }

  static GarageOrderStatus _status(String status) {
    return switch (status) {
      'received' => GarageOrderStatus.received,
      'diagnosing' => GarageOrderStatus.diagnosing,
      'awaiting_approval' => GarageOrderStatus.awaitingApproval,
      'awaiting_parts' => GarageOrderStatus.awaitingParts,
      'in_progress' => GarageOrderStatus.inProgress,
      'ready' => GarageOrderStatus.ready,
      'collected' => GarageOrderStatus.collected,
      'cancelled' => GarageOrderStatus.cancelled,
      _ => throw FormatException('Unknown Garage order status: $status'),
    };
  }
}
