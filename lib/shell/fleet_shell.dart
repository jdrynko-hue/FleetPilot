import 'package:flutter/material.dart';

import '../company/company_screen.dart';
import '../core/constants.dart';
import '../dashboard/dashboard_screen.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';
import '../drivers/drivers_screen.dart';
import '../garages/garages_screen.dart';
import '../issues/issues_screen.dart';
import '../repairs/repairs_screen.dart';
import '../vehicles/vehicles_screen.dart';

class FleetShell extends StatefulWidget {
  const FleetShell({required this.memberships, super.key});

  final List<CompanyMembership> memberships;

  @override
  State<FleetShell> createState() => _FleetShellState();
}

class _FleetShellState extends State<FleetShell> {
  final _repository = FleetRepository();
  int _index = 0;
  late CompanyMembership _membership;
  int _refreshToken = 0;

  @override
  void initState() {
    super.initState();
    _membership = widget.memberships.first;
  }

  void _refreshAll() => setState(() => _refreshToken++);

  @override
  Widget build(BuildContext context) {
    final canManage = canManageForRole(_membership.role);
    final pages = [
      DashboardScreen(
        company: _membership,
        refreshToken: _refreshToken,
      ),
      VehiclesScreen(
        company: _membership,
        canManage: canManage,
        refreshToken: _refreshToken,
        onDataChanged: _refreshAll,
      ),
      DriversScreen(
        company: _membership,
        canManage: canManage,
        refreshToken: _refreshToken,
        onDataChanged: _refreshAll,
      ),
      IssuesScreen(
        company: _membership,
        canManage: canManage,
        refreshToken: _refreshToken,
        onDataChanged: _refreshAll,
      ),
      RepairsScreen(
        company: _membership,
        canManage: canManage,
        refreshToken: _refreshToken,
        onDataChanged: _refreshAll,
      ),
      GaragesScreen(
        company: _membership,
        canManage: canManage,
        refreshToken: _refreshToken,
        onDataChanged: _refreshAll,
      ),
      CompanyScreen(company: _membership),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final body = IndexedStack(index: _index, children: pages);

        return Scaffold(
          appBar: AppBar(
            title: const Text('FleetPilot'),
            actions: [
              if (widget.memberships.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _membership.companyId,
                      items: widget.memberships
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.companyId,
                              child: Text(m.companyName),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() {
                          _membership = widget.memberships.firstWhere((m) => m.companyId == id);
                          _index = 0;
                          _refreshToken++;
                        });
                      },
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(child: Text(_membership.companyName)),
                ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refreshAll,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Sign out',
                onPressed: () => _repository.signOut(),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: (value) => setState(() => _index = value),
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), label: Text('Dashboard')),
                        NavigationRailDestination(icon: Icon(Icons.local_shipping_outlined), label: Text('Vehicles')),
                        NavigationRailDestination(icon: Icon(Icons.people_outline), label: Text('Drivers')),
                        NavigationRailDestination(icon: Icon(Icons.report_problem_outlined), label: Text('Issues')),
                        NavigationRailDestination(icon: Icon(Icons.build_outlined), label: Text('Repairs')),
                        NavigationRailDestination(icon: Icon(Icons.garage_outlined), label: Text('Garages')),
                        NavigationRailDestination(icon: Icon(Icons.business_outlined), label: Text('Company')),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _index > 4 ? 4 : _index,
                  onDestinationSelected: (value) {
                    if (value < 4) {
                      setState(() => _index = value);
                    } else {
                      _showMoreSheet(context);
                    }
                  },
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
                    NavigationDestination(icon: Icon(Icons.local_shipping_outlined), label: 'Vehicles'),
                    NavigationDestination(icon: Icon(Icons.people_outline), label: 'Drivers'),
                    NavigationDestination(icon: Icon(Icons.report_problem_outlined), label: 'Issues'),
                    NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
                  ],
                ),
        );
      },
    );
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.build_outlined),
              title: const Text('Repairs'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _index = 4);
              },
            ),
            ListTile(
              leading: const Icon(Icons.garage_outlined),
              title: const Text('Garages'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _index = 5);
              },
            ),
            ListTile(
              leading: const Icon(Icons.business_outlined),
              title: const Text('Company'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _index = 6);
              },
            ),
          ],
        ),
      ),
    );
  }
}
