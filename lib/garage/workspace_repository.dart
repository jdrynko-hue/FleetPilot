import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/billing_markets.dart';

/// Uses the existing tenant RLS and server-side owner membership trigger.
/// Creation alone does not opt into public bookings or activate billing.
class GarageWorkspaceRepository {
  const GarageWorkspaceRepository(this.client);
  final SupabaseClient client;

  static final invitationCode = RegExp(r'^[a-f0-9]{32}$');
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
  );

  Future<String> issueStaffInvitation({
    required String workspaceId,
    required String email,
    required String role,
  }) async {
    final result = await _staffRpc('garage_issue_staff_invite', {
      'p_workspace_id': workspaceId,
      'p_email': email.trim(),
      'p_role': role,
    });
    if (result is! String || !invitationCode.hasMatch(result)) {
      throw const FormatException('Workshop invitation not confirmed');
    }
    return result;
  }

  Future<String> acceptStaffInvitation(String code) async {
    if (!invitationCode.hasMatch(code)) {
      throw ArgumentError('Invalid invitation code');
    }
    final result = await _staffRpc('garage_accept_staff_invite', {'p_token': code});
    if (result is! String || !_uuid.hasMatch(result)) {
      throw const FormatException('Workshop membership not confirmed');
    }
    return result;
  }

  Future<Object?> _staffRpc(String function, Map<String, dynamic> params) async {
    final session = client.auth.currentSession;
    if (session == null) throw StateError('Sign in required');
    final result = await client.rpc(function, params: params)
        .timeout(const Duration(seconds: 15));
    if (client.auth.currentSession?.accessToken != session.accessToken) {
      throw StateError('Workshop invitation session changed');
    }
    return result;
  }

  Future<void> create({required String name, required String country}) async {
    final user = client.auth.currentUser;
    final currency = currencyForFleetCountry(country);
    if (user == null || user.emailConfirmedAt == null) {
      throw StateError('A verified account is required');
    }
    if (name.trim().length < 2 || name.trim().length > 160 || currency == null ||
        !supportedFleetCountries.containsKey(country)) {
      throw ArgumentError('Invalid workshop details');
    }
    final row = await client.from('garage_workspaces').insert({
      'owner_user_id': user.id,
      'name': name.trim(), 'country': country, 'currency': currency,
    }).select('id').single();
    if (client.auth.currentUser?.id != user.id) {
      throw StateError('Account changed');
    }
    final id = row['id'];
    if (id is! String || !_uuid.hasMatch(id)) {
      throw const FormatException('Workshop creation not confirmed');
    }
  }
}
