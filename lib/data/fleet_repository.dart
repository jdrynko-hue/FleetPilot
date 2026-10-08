import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class FleetRepository {
  FleetRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<bool> signUp({required String email, required String password}) async {
    final response = await _client.auth.signUp(email: email, password: password);
    return response.session != null;
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<List<CompanyMembership>> fetchMemberships() async {
    final user = currentUser;
    if (user == null) return [];

    final rows = await _client
        .from('company_members')
        .select('company_id, role, companies!inner(name, currency)')
        .eq('user_id', user.id)
        .order('created_at');

    return (rows as List)
        .map((row) => CompanyMembership.fromJson((row as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<String> createCompany({
    required String name,
    required String country,
    required String currency,
  }) async {
    final result = await _client.rpc(
      'create_company_for_current_user',
      params: {
        '_name': name,
        '_country': country,
        '_currency': currency,
      },
    );
    return result.toString();
  }

  Future<List<Vehicle>> fetchVehicles(String companyId) async {
    final rows = await _client
        .from('vehicles')
        .select('*, drivers(name)')
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('registration');
    return (rows as List)
        .map((row) => Vehicle.fromJson((row as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<Vehicle> fetchVehicle(String companyId, String vehicleId) async {
    final row = await _client
        .from('vehicles')
        .select('*, drivers(name)')
        .eq('company_id', companyId)
        .eq('id', vehicleId)
        .single();
    return Vehicle.fromJson(row);
  }

  Future<void> createVehicle(Json values) async {
    await _client.from('vehicles').insert(values);
  }

  Future<void> updateVehicle(String id, Json values) async {
    await _client.from('vehicles').update(values).eq('id', id);
  }

  Future<void> archiveVehicle(String id) async {
    await _client.from('vehicles').update({
      'is_active': false,
      'archived_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<List<Driver>> fetchDrivers(String companyId) async {
    final rows = await _client
        .from('drivers')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('name');
    return (rows as List)
        .map((row) => Driver.fromJson((row as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> createDriver(Json values) async {
    await _client.from('drivers').insert(values);
  }

  Future<void> updateDriver(String id, Json values) async {
    await _client.from('drivers').update(values).eq('id', id);
  }

  Future<void> archiveDriver(String id) async {
    await _client.from('drivers').update({'is_active': false}).eq('id', id);
  }

  Future<List<Garage>> fetchGarages(String companyId) async {
    final rows = await _client
        .from('garages')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('name');
    return (rows as List)
        .map((row) => Garage.fromJson((row as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> createGarage(Json values) async {
    await _client.from('garages').insert(values);
  }

  Future<void> updateGarage(String id, Json values) async {
    await _client.from('garages').update(values).eq('id', id);
  }

  Future<void> archiveGarage(String id) async {
    await _client.from('garages').update({'is_active': false}).eq('id', id);
  }

  Future<List<FleetIssue>> fetchIssues(String companyId, {String? vehicleId}) async {
    var query = _client
        .from('issues')
        .select('*, vehicles!inner(registration)')
        .eq('company_id', companyId);
    if (vehicleId != null) query = query.eq('vehicle_id', vehicleId);
    final rows = await query.order('reported_at', ascending: false);
    return (rows as List)
        .map((row) => FleetIssue.fromJson((row as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> createIssue(Json values) async {
    await _client.from('issues').insert(values);
  }

  Future<void> updateIssue(String id, Json values) async {
    await _client.from('issues').update(values).eq('id', id);
  }

  Future<List<Repair>> fetchRepairs(String companyId, {String? vehicleId}) async {
    var query = _client
        .from('repairs')
        .select('*, vehicles!inner(registration), garages(name)')
        .eq('company_id', companyId);
    if (vehicleId != null) query = query.eq('vehicle_id', vehicleId);
    final rows = await query.order('created_at', ascending: false);
    return (rows as List)
        .map((row) => Repair.fromJson((row as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> createRepair(Json values) async {
    await _client.from('repairs').insert(values);
  }

  Future<void> updateRepair(String id, Json values) async {
    await _client.from('repairs').update(values).eq('id', id);
  }
}
