import 'package:supabase_flutter/supabase_flutter.dart';

enum EcosystemModule { fleet, workshop, mechanic, customer }

class EcosystemDestination {
  const EcosystemDestination(this.module, {this.workspaceId, this.name, this.country, this.canConfigure = false});
  final EcosystemModule module;
  final String? workspaceId;
  final String? name;
  final String? country;
  final bool canConfigure;
}

class EcosystemAccess {
  const EcosystemAccess({required this.hasFleet, required this.garages});
  final bool hasFleet;
  final List<EcosystemDestination> garages;
}

typedef MembershipRows = Future<Object?> Function(String userId);

/// Memberships are server-filtered RLS rows, never editable Auth metadata.
/// This discovery controls navigation; each module still enforces server ACLs.
class EcosystemAccessRepository {
  const EcosystemAccessRepository({
    required this.currentUserId,
    required this.fleetRows,
    required this.garageRows,
  });

  factory EcosystemAccessRepository.forClient(SupabaseClient client) =>
      EcosystemAccessRepository(
        currentUserId: () => client.auth.currentUser?.id,
        fleetRows: (id) => client.from('company_members')
            .select('user_id,company_id,role').eq('user_id', id),
        garageRows: (id) => client.from('garage_members')
            .select('user_id,workspace_id,role,garage_workspaces(name,country)')
            .eq('user_id', id),
      );

  final String? Function() currentUserId;
  final MembershipRows fleetRows;
  final MembershipRows garageRows;
  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');

  Future<EcosystemAccess> load() async {
    final user = currentUserId();
    if (user == null) throw StateError('Sign in required');
    final results = await Future.wait([
      fleetRows(user), garageRows(user),
    ]).timeout(const Duration(seconds: 12));
    if (currentUserId() != user) throw StateError('Account changed');
    final fleet = _rows(results[0], user, 'company_id',
        {'owner', 'admin', 'manager', 'viewer', 'driver'});
    final garage = _rows(results[1], user, 'workspace_id',
        {'owner', 'service_adviser', 'mechanic'});
    final destinations = <EcosystemDestination>[];
    for (final row in garage) {
      final workspace = row['garage_workspaces'];
      if (workspace is! Map || workspace['name'] is! String ||
          (workspace['name'] as String).trim().isEmpty) {
        throw const FormatException('Missing workspace');
      }
      destinations.add(EcosystemDestination(
        row['role'] == 'mechanic'
            ? EcosystemModule.mechanic : EcosystemModule.workshop,
        workspaceId: row['workspace_id'] as String,
        name: workspace['name'] as String,
        country: workspace['country'] is String ? workspace['country'] as String : null,
        canConfigure: row['role'] == 'owner',
      ));
    }
    return EcosystemAccess(
      hasFleet: fleet.isNotEmpty,
      garages: List.unmodifiable(destinations),
    );
  }

  static List<Map> _rows(Object? data, String user, String scope,
      Set<String> roles) {
    if (data is! List) throw const FormatException('Invalid memberships');
    final rows = <Map>[];
    final ids = <String>{};
    for (final row in data) {
      if (row is! Map || row['user_id'] != user || row[scope] is! String ||
          !_uuid.hasMatch(row[scope] as String) ||
          !roles.contains(row['role']) || !ids.add(row[scope] as String)) {
        throw const FormatException('Invalid membership');
      }
      rows.add(row);
    }
    return rows;
  }
}
