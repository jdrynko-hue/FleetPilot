import 'package:flutter/material.dart';

import '../data/fleet_repository.dart';
import '../data/models.dart';
import '../shell/fleet_shell.dart';
import 'create_company_screen.dart';

class CompanyGate extends StatefulWidget {
  const CompanyGate({super.key});

  @override
  State<CompanyGate> createState() => _CompanyGateState();
}

class _CompanyGateState extends State<CompanyGate> {
  final _repository = FleetRepository();
  late Future<List<CompanyMembership>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _repository.fetchMemberships();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CompanyMembership>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(snapshot.error.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(_reload),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final memberships = snapshot.data ?? [];
        if (memberships.isEmpty) {
          return CreateCompanyScreen(onCreated: () => setState(_reload));
        }

        return FleetShell(memberships: memberships);
      },
    );
  }
}
