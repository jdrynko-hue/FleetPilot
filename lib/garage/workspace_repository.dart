import 'package:supabase_flutter/supabase_flutter.dart';

import 'billing_markets.dart';

/// Uses the existing tenant RLS and server-side owner membership trigger.
/// Creation alone does not opt into public bookings or activate billing.
class GarageWorkspaceRepository {
  const GarageWorkspaceRepository(this.client);
  final SupabaseClient client;

  Future<void> create({required String name, required String country}) async {
    final user = client.auth.currentUser;
    final currency = currencyForGarageCountry(country);
    if (user == null || user.emailConfirmedAt == null) {
      throw StateError('A verified account is required');
    }
    if (name.trim().length < 2 || name.trim().length > 160 || currency == null ||
        !supportedGarageCountries.containsKey(country)) {
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
    if (id is! String || !RegExp(
        r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(id)) {
      throw const FormatException('Workshop creation not confirmed');
    }
  }
}
