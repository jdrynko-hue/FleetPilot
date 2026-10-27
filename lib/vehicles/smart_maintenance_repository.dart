import 'package:supabase_flutter/supabase_flutter.dart';

import 'smart_maintenance.dart';

/// Source-only QA adapter. Row-level isolation and manager permissions must
/// be enforced in PostgreSQL; these UI guards are defense in depth.
class SmartMaintenanceRepository {
  const SmartMaintenanceRepository(this.client);
  final SupabaseClient client;

  Future<T> _sessionBound<T>(Future<T> Function() request) async {
    final actor = client.auth.currentUser?.id;
    final token = client.auth.currentSession?.accessToken;
    if (actor == null || token == null || token.isEmpty) {
      throw StateError('Sign in as a Fleet manager');
    }
    final answer = await request();
    if (client.auth.currentUser?.id != actor ||
        client.auth.currentSession?.accessToken != token) {
      // Mutations may already be committed, so do not retry automatically.
      throw StateError('Session changed; refresh before continuing');
    }
    return answer;
  }

  Future<List<MaintenancePlan>> plans(String companyId, String vehicleId) =>
      _sessionBound(() async {
        final rows = await client.from('fleet_maintenance_plans')
          .select()
          .eq('company_id', companyId)
          .eq('vehicle_id', vehicleId)
          .order('kind');
        return List<MaintenancePlan>.unmodifiable(
          rows.map((row) => MaintenancePlan.fromJson(row)));
      });

  Future<List<MaintenanceAlert>> alerts(
      String companyId, String vehicleId) => _sessionBound(() async {
        final rows = await client.from('fleet_maintenance_alerts')
          .select('plan_id,cycle,kind,stage,source,created_at,due_miles,due_date')
          .eq('company_id', companyId)
          .eq('vehicle_id', vehicleId)
          .order('created_at', ascending: false)
          .limit(30);
        return List<MaintenanceAlert>.unmodifiable(
          rows.map((row) => MaintenanceAlert.fromJson(row)));
      });

  Future<List<MaintenanceHistory>> history(
      String companyId, String vehicleId) => _sessionBound(() async {
        final rows = await client.from('fleet_maintenance_history')
          .select('kind,completed_date,completed_miles,note')
          .eq('company_id', companyId)
          .eq('vehicle_id', vehicleId)
          .order('completed_date', ascending: false)
          .limit(50);
        return List<MaintenanceHistory>.unmodifiable(
          rows.map((row) => MaintenanceHistory.fromJson(row)));
      });

  Future<List<MaintenanceOdometerReading>> readings(
      String companyId, String vehicleId) => _sessionBound(() async {
        final rows = await client.from('fleet_maintenance_odometer_readings')
          .select('odometer_miles,recorded_date')
          .eq('company_id', companyId)
          .eq('vehicle_id', vehicleId)
          .order('recorded_date', ascending: false)
          .limit(2);
        return List<MaintenanceOdometerReading>.unmodifiable(rows.map(
          (row) => MaintenanceOdometerReading(
            (row['odometer_miles'] as num).toInt(),
            DateTime.parse(row['recorded_date'].toString()),
          )));
      });

  Future<String> setPlan({
    required String companyId,
    required String vehicleId,
    required MaintenanceKind kind,
    required MaintenanceUnit unit,
    required int? intervalDistance,
    required int? intervalMonths,
    required int lastServiceMiles,
    required DateTime lastServiceDate,
    String? notes,
  }) => _sessionBound(() async {
    final result = await client.rpc('fleet_maintenance_set_plan', params: {
      'p_company': companyId,
      'p_vehicle': vehicleId,
      'p_kind': maintenanceCodes[kind],
      'p_unit': unit.name,
      'p_distance': intervalDistance,
      'p_months': intervalMonths,
      'p_last_miles': lastServiceMiles,
      'p_last_date': lastServiceDate.toIso8601String().split('T').first,
      'p_notes': notes,
    });
    if (result is! String || result.isEmpty) {
      throw const FormatException('Invalid maintenance plan response');
    }
    return result;
  });

  Future<String> complete({
    required String companyId,
    required String planId,
    required int completedMiles,
    required DateTime completedDate,
    String note = '',
  }) => _sessionBound(() async {
    final result = await client.rpc('fleet_maintenance_complete', params: {
      'p_company': companyId,
      'p_plan': planId,
      'p_completed_miles': completedMiles,
      'p_completed_date': completedDate.toIso8601String().split('T').first,
      'p_note': note,
    });
    if (result is! String || result.isEmpty) {
      throw const FormatException('Invalid maintenance completion response');
    }
    return result;
  });

  Future<int> recordOdometer({
    required String companyId,
    required String vehicleId,
    required int miles,
    required DateTime date,
  }) => _sessionBound(() async {
    final result = await client.rpc('fleet_maintenance_record_miles', params: {
      'p_company': companyId,
      'p_vehicle': vehicleId,
      'p_miles': miles,
      'p_date': date.toIso8601String().split('T').first,
    });
    if (result is! num || result.toInt() != miles) {
      throw const FormatException('Invalid odometer confirmation');
    }
    return result.toInt();
  });
}
