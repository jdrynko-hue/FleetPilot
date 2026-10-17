import 'package:supabase_flutter/supabase_flutter.dart';
import 'repair_bridge_repository.dart';

/// Existing QA RPCs retain all role, state and latest-approval checks.
class GarageOrderActionsRepository {
  const GarageOrderActionsRepository(this.client);
  final SupabaseClient client;

  Future<Object?> _call(String rpc, String workspace, String order,
      [Map<String, Object?> extra = const {}]) async {
    GarageRepairBridgeRepository.requireId(workspace, 'workspace');
    GarageRepairBridgeRepository.requireId(order, 'order');
    final user = client.auth.currentUser?.id;
    if (user == null) throw StateError('Sign in required');
    final result = await client.rpc(rpc, params: {
      'p_workspace_id': workspace, 'p_order_id': order, ...extra,
    });
    if (client.auth.currentUser?.id != user) throw StateError('Account changed');
    return result;
  }

  Future<String> advance(String workspace, String order, String target) async {
    final rpc = switch (target) {
      'diagnosing' => 'garage_begin_diagnosis',
      'in_progress' => 'garage_start_approved_repair',
      _ => throw ArgumentError.value(target, 'target'),
    };
    final result = await _call(rpc, workspace, order);
    if (result != target) throw const FormatException('Unexpected order status');
    return target;
  }

  Future<String> assign(String workspace, String order, String mechanic) async {
    GarageRepairBridgeRepository.requireId(mechanic, 'mechanic');
    final result = await _call('garage_assign_mechanic', workspace, order,
      {'p_mechanic_user_id': mechanic});
    if (result != mechanic) throw const FormatException('Unexpected assignee');
    return mechanic;
  }
}
