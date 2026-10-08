import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/widgets.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import 'driver_form_screen.dart';

class DriversScreen extends StatefulWidget {
  const DriversScreen({
    required this.company,
    required this.canManage,
    required this.refreshToken,
    required this.onDataChanged,
    super.key,
  });

  final CompanyMembership company;
  final bool canManage;
  final int refreshToken;
  final VoidCallback onDataChanged;

  @override
  State<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends State<DriversScreen> {
  final _repository = FleetRepository();
  late Future<List<Driver>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DriversScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.company.companyId != widget.company.companyId) {
      _load();
    }
  }

  void _load() => _future = _repository.fetchDrivers(widget.company.companyId);

  Future<void> _open({Driver? driver}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DriverFormScreen(company: widget.company, driver: driver)),
    );
    if (changed == true) {
      setState(_load);
      widget.onDataChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Driver>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorState(error: snapshot.error!, onRetry: () => setState(_load));
        }
        final drivers = snapshot.data ?? [];
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: widget.canManage
              ? FloatingActionButton.extended(
                  onPressed: () => _open(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add driver'),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: () async => setState(_load),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text('Drivers', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 16),
                if (drivers.isEmpty)
                  const SizedBox(
                    height: 360,
                    child: EmptyState(
                      icon: Icons.people_outline,
                      title: 'No drivers yet',
                      message: 'Driver records will be available to assign to vehicles and future issue reports.',
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < drivers.length; i++) ...[
                          ListTile(
                            onTap: widget.canManage ? () => _open(driver: drivers[i]) : null,
                            leading: CircleAvatar(child: Text(drivers[i].name.isEmpty ? '?' : drivers[i].name[0].toUpperCase())),
                            title: Text(drivers[i].name),
                            subtitle: Text([
                              if ((drivers[i].phone ?? '').isNotEmpty) drivers[i].phone!,
                              if ((drivers[i].employeeReference ?? '').isNotEmpty) drivers[i].employeeReference!,
                            ].join(' • ')),
                            trailing: StatusPill(label: prettifyEnum(drivers[i].status)),
                          ),
                          if (i != drivers.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 84),
              ],
            ),
          ),
        );
      },
    );
  }
}
