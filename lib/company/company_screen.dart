import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';

class CompanyScreen extends StatelessWidget {
  const CompanyScreen({required this.company, super.key});

  final CompanyMembership company;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Company', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(company.companyName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text('Your role: ${prettifyEnum(company.role)}'),
                Text('Currency: ${company.currency}'),
                const SizedBox(height: 16),
                const Text(
                  'Team invitations, billing, audit history and role management are intentionally reserved for a later release. The database is already structured for multiple members per company.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => FleetRepository().signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
